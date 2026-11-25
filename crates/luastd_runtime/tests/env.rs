//! `luastd.env`: permission checks, async prompts and the overlay.
#![cfg(feature = "env")]

mod common;

use std::cell::RefCell;
use std::future::Future;
use std::pin::Pin;
use std::rc::Rc;

use luastd_runtime::deno_permissions::PermissionsOptions;
use luastd_runtime::{Env, PromptDecision, PromptRequest, Prompter, Runtime, permissions};

/// Allows `HOME`, denies everything else, and records every request.
#[derive(Clone, Default)]
struct Recorder(Rc<RefCell<Vec<PromptRequest>>>);

impl Prompter for Recorder {
    fn prompt(&self, request: PromptRequest) -> Pin<Box<dyn Future<Output = PromptDecision>>> {
        let decision = match request.target.as_deref() {
            Some("HOME") => PromptDecision::Allow,
            _ => PromptDecision::Deny,
        };
        self.0.borrow_mut().push(request);
        Box::pin(async move {
            tokio::task::yield_now().await; // a real prompt waits for input
            decision
        })
    }
}

fn options(prompt: bool) -> PermissionsOptions {
    PermissionsOptions {
        allow_env: Some(vec!["PATH".into(), "LUASTD_SPEC".into()]),
        deny_env: Some(vec!["LUASTD_SPEC_DENIED".into()]),
        prompt,
        ..Default::default()
    }
}

fn runtime(prompt: bool, recorder: &Recorder) -> Runtime {
    Runtime::builder()
        .permissions(permissions::from_options(&options(prompt)).unwrap())
        .prompter(recorder.clone())
        .effect::<Env>()
        .build()
        .unwrap()
}

#[test]
fn env_spec() {
    let recorder = Recorder::default();
    let rt = runtime(true, &recorder);
    common::run_spec(
        &rt,
        "luastd_env_spec.lua",
        include_str!("lua/luastd_env_spec.lua"),
    );
    let targets: Vec<_> = recorder
        .0
        .borrow()
        .iter()
        .map(|r| r.target.clone())
        .collect();
    // HOME is asked once and remembered; USER is asked once and denied for good.
    assert_eq!(
        targets
            .iter()
            .filter(|t| t.as_deref() == Some("HOME"))
            .count(),
        1,
        "{targets:?}"
    );
    assert_eq!(
        targets
            .iter()
            .filter(|t| t.as_deref() == Some("USER"))
            .count(),
        1,
        "{targets:?}"
    );
    assert!(!targets.iter().any(|t| t.as_deref() == Some("PATH")));
}

#[test]
fn prompter_is_not_asked_when_the_container_never_prompts() {
    let recorder = Recorder::default();
    let rt = runtime(false, &recorder);
    let kind: String = rt
        .run(async |lua| {
            lua.load(
                r#"
                local ok, err = pcall(require("luastd.env").get, "HOME")
                assert(not ok)
                return err.kind
                "#,
            )
            .eval_async()
            .await
        })
        .unwrap();
    assert_eq!(kind, "PermissionDenied");
    assert!(recorder.0.borrow().is_empty());
}

#[test]
fn no_prompter_means_denied() {
    let rt = Runtime::builder()
        .permissions(permissions::from_options(&options(true)).unwrap())
        .effect::<Env>()
        .build()
        .unwrap();
    let message: String = rt
        .run(async |lua| {
            lua.load(
                r#"local _, err = pcall(require("luastd.env").get, "HOME"); return tostring(err)"#,
            )
            .eval_async()
            .await
        })
        .unwrap();
    assert!(message.starts_with("PermissionDenied: "), "{message}");
    assert!(message.contains("no prompter"), "{message}");
}

#[test]
fn set_never_touches_the_process() {
    let rt = Runtime::builder()
        .permissions(permissions::allow_all())
        .effect::<Env>()
        .build()
        .unwrap();
    rt.run(async |lua| {
        lua.load(r#"require("luastd.env").set("LUASTD_SPEC_OVERLAY", "1")"#)
            .exec_async()
            .await?;
        Ok(())
    })
    .unwrap();
    assert!(std::env::var_os("LUASTD_SPEC_OVERLAY").is_none());
    let seen: String = rt
        .run(async |lua| {
            lua.load(r#"return require("luastd.env").get("LUASTD_SPEC_OVERLAY")"#)
                .eval_async()
                .await
        })
        .unwrap();
    assert_eq!(seen, "1");
}

/// A host that never answers, like a modal the user leaves open.
struct Never;

impl Prompter for Never {
    fn prompt(&self, _: PromptRequest) -> Pin<Box<dyn Future<Output = PromptDecision>>> {
        Box::pin(std::future::pending())
    }
}

#[test]
fn a_pending_prompt_is_a_cancellation_point() {
    let rt = Runtime::builder()
        .permissions(permissions::from_options(&options(true)).unwrap())
        .prompter(Never)
        .effect::<Env>()
        .build()
        .unwrap();
    let kind: String = rt
        .run(async |lua| {
            lua.load(
                r#"
                local async, env = require("luastd.async"), require("luastd.env")
                local ok, err = pcall(async.with_timeout, 10, function () return env.get("HOME") end)
                assert(not ok)
                return err.kind
                "#,
            )
            .eval_async()
            .await
        })
        .unwrap();
    assert_eq!(kind, "Timeout");
}
