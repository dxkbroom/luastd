//! Async permission prompts (ADR 0004).
//!
//! deno's prompter is synchronous and process-global. luastd installs
//! [`StagedPrompter`] globally: it answers `Deny` unless luastd has staged the
//! host's answer on the current thread. A check that hits the `prompt` state
//! awaits the host's async [`Prompter`], stages its decision, and lets deno's
//! `request_*` record it in the [`PermissionsContainer`]. Only the asking
//! coroutine waits; the container stays the single source of truth.

// The checks serve effect modules; with none compiled in they sit unused.
#![cfg_attr(not(feature = "env"), allow(dead_code))]

use std::cell::Cell;
use std::future::Future;
use std::pin::Pin;
use std::rc::Rc;
use std::sync::Once;

use deno_permissions::prompter::{
    GetFormattedStackFn, PermissionPrompter, PromptResponse, set_prompter,
};
use deno_permissions::{PermissionState, PermissionsContainer};
use mlua::Lua;

use crate::errors::LuaError;

/// What a check asks the host to decide.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PromptRequest {
    /// deno's permission name, such as `"env"`.
    pub permission: &'static str,
    /// The descriptor, such as the variable name; `None` means "all".
    pub target: Option<String>,
    /// A human-readable question, such as `env access to "HOME"`.
    pub message: String,
}

/// The host's answer to a [`PromptRequest`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PromptDecision {
    /// Grant this descriptor.
    Allow,
    /// Deny this descriptor; deno remembers it and will not ask again.
    Deny,
    /// Grant the whole permission (every variable, for `env`).
    AllowAll,
}

/// A host-supplied, asynchronous prompt, such as a TUI modal.
///
/// Runs on the Lua thread; the returned future may await user input.
pub trait Prompter {
    fn prompt(&self, request: PromptRequest) -> Pin<Box<dyn Future<Output = PromptDecision>>>;
}

/// The host's prompter, stored in the Lua state's app data.
#[derive(Clone)]
pub(crate) struct PrompterSlot(pub Rc<dyn Prompter>);

thread_local! {
    static STAGED: Cell<Option<PromptDecision>> = const { Cell::new(None) };
}

/// The process-global deno prompter luastd installs.
struct StagedPrompter;

impl PermissionPrompter for StagedPrompter {
    fn prompt(
        &mut self,
        _message: &str,
        _name: &str,
        _api_name: Option<&str>,
        _is_unary: bool,
        _get_stack: Option<GetFormattedStackFn>,
    ) -> PromptResponse {
        match STAGED.with(Cell::take) {
            Some(PromptDecision::Allow) => PromptResponse::Allow,
            Some(PromptDecision::AllowAll) => PromptResponse::AllowAll,
            Some(PromptDecision::Deny) | None => PromptResponse::Deny,
        }
    }
}

/// Replace deno's TTY prompter with [`StagedPrompter`], once per process.
pub(crate) fn install_global_prompter() {
    static INSTALL: Once = Once::new();
    INSTALL.call_once(|| set_prompter(Box::new(StagedPrompter)));
}

/// Run `request` with `decision` staged for deno's synchronous prompt.
fn with_staged<T>(decision: PromptDecision, request: impl FnOnce() -> T) -> T {
    STAGED.with(|staged| staged.set(Some(decision)));
    let result = request();
    STAGED.with(|staged| staged.set(None));
    result
}

/// One kind of permission, with deno's query/request/check for it.
pub(crate) trait Descriptor {
    const PERMISSION: &'static str;
    fn target(&self) -> Option<String>;
    fn query(&self, container: &PermissionsContainer) -> PermissionState;
    fn request(&self, container: &PermissionsContainer) -> PermissionState;
    fn check(&self, container: &PermissionsContainer) -> Result<(), String>;
}

/// An environment variable, or every variable when `None`.
pub(crate) struct EnvDescriptor<'a>(pub Option<&'a str>);

impl Descriptor for EnvDescriptor<'_> {
    const PERMISSION: &'static str = "env";

    fn target(&self) -> Option<String> {
        self.0.map(str::to_owned)
    }

    fn query(&self, container: &PermissionsContainer) -> PermissionState {
        container.query_env(self.0)
    }

    fn request(&self, container: &PermissionsContainer) -> PermissionState {
        container.request_env(self.0)
    }

    fn check(&self, container: &PermissionsContainer) -> Result<(), String> {
        match self.0 {
            Some(var) => container.check_env(var),
            None => container.check_env_all(),
        }
        .map_err(|error| error.to_string())
    }
}

fn denied<D: Descriptor>(descriptor: &D, message: String) -> LuaError {
    let error = LuaError::new("PermissionDenied", message).with("permission", D::PERMISSION);
    match descriptor.target() {
        Some(target) => error.with("target", target),
        None => error,
    }
}

fn question<D: Descriptor>(descriptor: &D) -> String {
    match descriptor.target() {
        Some(target) => format!("{} access to \"{target}\"", D::PERMISSION),
        None => format!("{} access", D::PERMISSION),
    }
}

/// Check `descriptor`, awaiting the host's [`Prompter`] when deno would prompt.
pub(crate) async fn check<D: Descriptor>(
    lua: &Lua,
    container: &PermissionsContainer,
    descriptor: D,
) -> Result<(), LuaError> {
    if descriptor.query(container) == PermissionState::Prompt {
        let prompter = lua
            .app_data_ref::<PrompterSlot>()
            .map(|slot| slot.0.clone());
        let Some(prompter) = prompter else {
            return Err(denied(
                &descriptor,
                format!(
                    "{} has not been granted; no prompter is installed",
                    question(&descriptor)
                ),
            ));
        };
        // A snapshot tells whether this container prompts at all, without
        // asking the host for an answer deno would ignore.
        let probe = container.deep_clone();
        if with_staged(PromptDecision::Allow, || descriptor.request(&probe))
            != PermissionState::Granted
        {
            return Err(denied(
                &descriptor,
                format!("{} has not been granted", question(&descriptor)),
            ));
        }
        let request = PromptRequest {
            permission: D::PERMISSION,
            target: descriptor.target(),
            message: question(&descriptor),
        };
        // Cancelling the coroutine abandons the question; nothing is recorded.
        let Some(decision) = crate::cancellable(lua, prompter.prompt(request)).await else {
            return Err(LuaError::cancelled());
        };
        with_staged(decision, || descriptor.request(container));
    }
    descriptor
        .check(container)
        .map_err(|message| denied(&descriptor, message))
}
