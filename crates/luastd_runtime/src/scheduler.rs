//! The Rust core of `luastd.async`: jobs, scopes, cancellation and channels.
//!
//! Every launched job is a Lua thread driven by `Thread::into_async` on the
//! runtime's `LocalSet`. Jobs and scopes are [`Node`]s in a tree; each owns a
//! [`CancellationToken`] derived from its parent's, so cancelling a node
//! cancels everything below it. A thread's *stack* of entries records which
//! node it currently runs in (`scope` pushes, settling pops); threads the
//! scheduler did not create, such as the main chunk, start at the root.
//!
//! Suspension points (`delay`, `join`, `send`, `receive`, prompts) race the
//! current token and report cancellation instead of a value. The Lua prelude
//! (`async.lua`) turns that into raising the shared cancellation error, which
//! keeps its identity even through Rust frames (ADR 0006).

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::future::Future;
use std::rc::{Rc, Weak};
use std::time::Duration;

use mlua::{AnyUserData, Function, Lua, MultiValue, Result, Table, UserData, UserDataRef, Value};
use tokio::sync::Notify;
use tokio::task::JoinHandle;
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;

use crate::errors::cancelled;

const UNATTACHED_CHILD: usize = usize::MAX;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Kind {
    Root,
    Launch,
    Async,
    Scope,
    Supervisor,
    Timeout,
}

impl Kind {
    fn is_job(self) -> bool {
        matches!(self, Kind::Launch | Kind::Async)
    }
}

/// How a node ended; `Timeout` only for `with_timeout` scopes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Status {
    Ok,
    Failed,
    Cancelled,
    Timeout,
}

impl Status {
    fn as_str(self) -> &'static str {
        match self {
            Status::Ok => "ok",
            Status::Failed => "failed",
            Status::Cancelled => "cancelled",
            Status::Timeout => "timeout",
        }
    }

    fn parse(s: &str) -> Result<Self> {
        Ok(match s {
            "ok" => Status::Ok,
            "failed" => Status::Failed,
            "cancelled" => Status::Cancelled,
            "timeout" => Status::Timeout,
            other => return Err(mlua::Error::runtime(format!("unknown status {other:?}"))),
        })
    }
}

/// A job or a scope.
pub(crate) struct Node {
    kind: Kind,
    parent: Option<Weak<Node>>,
    /// Slot in the parent's child vector, or `UNATTACHED_CHILD` for roots.
    parent_index: Cell<usize>,
    /// Coroutine name inherited from the parent context, if any.
    coroutine_name: Option<String>,
    token: CancellationToken,
    /// Running child jobs; each removes itself when it completes.
    children: RefCell<Vec<Rc<Node>>>,
    /// The first failure of a child job, for non-supervisor nodes.
    child_failure: RefCell<Option<Value>>,
    timed_out: Cell<bool>,
    timer: RefCell<Option<JoinHandle<()>>>,
    on_cancel: RefCell<Vec<Function>>,
    result: RefCell<Option<(Status, Value)>>,
    done: Notify,
    /// Lazy jobs are not scheduled until `start_job` is called.
    lazy: Cell<bool>,
    started: Cell<bool>,
    start_notify: Notify,
}

impl Node {
    fn new(
        kind: Kind,
        parent: Option<&Rc<Node>>,
        token: CancellationToken,
        coroutine_name: Option<String>,
    ) -> Rc<Self> {
        let coroutine_name =
            coroutine_name.or_else(|| parent.and_then(|parent| parent.coroutine_name.clone()));
        Rc::new(Self {
            kind,
            parent: parent.map(Rc::downgrade),
            parent_index: Cell::new(UNATTACHED_CHILD),
            coroutine_name,
            token,
            children: RefCell::default(),
            child_failure: RefCell::default(),
            timed_out: Cell::new(false),
            timer: RefCell::default(),
            on_cancel: RefCell::default(),
            result: RefCell::default(),
            done: Notify::new(),
            lazy: Cell::new(false),
            started: Cell::new(true),
            start_notify: Notify::new(),
        })
    }

    fn supervisor(&self) -> bool {
        matches!(self.kind, Kind::Root | Kind::Supervisor)
    }

    fn is_done(&self) -> bool {
        self.result.borrow().is_some()
    }

    fn add_child(parent: &Rc<Self>, child: Rc<Self>) {
        let mut children = parent.children.borrow_mut();
        let index = children.len();
        debug_assert_eq!(child.parent_index.get(), UNATTACHED_CHILD);
        child.parent_index.set(index);
        children.push(child);
    }

    fn remove_child(parent: &Self, child: &Self) {
        let index = child.parent_index.get();
        assert_ne!(
            index, UNATTACHED_CHILD,
            "completed node was not attached to its parent"
        );
        let mut children = parent.children.borrow_mut();
        assert!(
            index < children.len(),
            "scheduler child index is out of bounds"
        );
        let removed = children.swap_remove(index);
        assert!(
            std::ptr::eq(removed.as_ref(), child),
            "scheduler child index points to another node"
        );
        child.parent_index.set(UNATTACHED_CHILD);
        if let Some(moved) = children.get(index) {
            moved.parent_index.set(index);
        }
    }

    /// Wait for completion; not cancellable (callers wrap it when needed).
    async fn wait_done(&self) {
        loop {
            let notified = self.done.notified();
            if self.is_done() {
                return;
            }
            notified.await;
        }
    }

    async fn wait_children(&self) {
        loop {
            let first = self.children.borrow().first().cloned();
            match first {
                Some(child) => child.wait_done().await,
                None => return,
            }
        }
    }
}

/// A node as Lua sees it; the prelude wraps it in a Job or Scope object.
#[derive(Clone)]
pub(crate) struct Handle(Rc<Node>);

impl UserData for Handle {}

#[derive(Clone)]
enum Entry {
    Node(Rc<Node>),
    /// Inside `async.finally` cleanup and `on_cancel` handlers.
    NonCancellable,
}

pub(crate) struct Scheduler {
    root: RefCell<Rc<Node>>,
    detached_jobs: RefCell<Vec<Rc<Node>>>,
    stacks: RefCell<HashMap<usize, Vec<Entry>>>,
    runner: RefCell<Option<Function>>,
    running: Cell<bool>,
    epoch: Instant,
    unhandled: RefCell<Option<UnhandledHandler>>,
}

impl Scheduler {
    fn new() -> Self {
        Self {
            root: RefCell::new(Node::new(Kind::Root, None, CancellationToken::new(), None)),
            detached_jobs: RefCell::default(),
            stacks: RefCell::default(),
            runner: RefCell::default(),
            running: Cell::new(false),
            epoch: Instant::now(),
            unhandled: RefCell::default(),
        }
    }

    fn root(&self) -> Rc<Node> {
        self.root.borrow().clone()
    }

    fn detached_jobs(&self) -> Vec<Rc<Node>> {
        self.detached_jobs.borrow().clone()
    }

    fn top(&self, key: usize) -> Entry {
        self.stacks
            .borrow()
            .get(&key)
            .and_then(|stack| stack.last().cloned())
            .unwrap_or_else(|| Entry::Node(self.root()))
    }

    fn current_node(&self, key: usize) -> Rc<Node> {
        let stacks = self.stacks.borrow();
        stacks
            .get(&key)
            .and_then(|stack| {
                stack.iter().rev().find_map(|entry| match entry {
                    Entry::Node(node) => Some(node.clone()),
                    Entry::NonCancellable => None,
                })
            })
            .unwrap_or_else(|| self.root())
    }

    fn current_token(&self, key: usize) -> CancellationToken {
        match self.top(key) {
            Entry::Node(node) => node.token.clone(),
            Entry::NonCancellable => CancellationToken::new(),
        }
    }

    fn push(&self, key: usize, entry: Entry) {
        let root = self.root();
        self.stacks
            .borrow_mut()
            .entry(key)
            .or_insert_with(|| vec![Entry::Node(root)])
            .push(entry);
    }

    fn pop(&self, key: usize) {
        let mut stacks = self.stacks.borrow_mut();
        if let Some(stack) = stacks.get_mut(&key) {
            stack.pop();
            let only_root = stack.len() == 1
                && matches!(&stack[0], Entry::Node(node) if node.kind == Kind::Root);
            if stack.is_empty() || only_root {
                stacks.remove(&key);
            }
        }
    }
}

fn scheduler(lua: &Lua) -> Result<Rc<Scheduler>> {
    lua.app_data_ref::<Rc<Scheduler>>()
        .map(|s| s.clone())
        .ok_or_else(|| mlua::Error::runtime("luastd.async is not installed"))
}

fn thread_key(lua: &Lua) -> usize {
    lua.current_thread().to_pointer() as usize
}

/// Race `future` against cancellation of the calling coroutine's context.
///
/// Returns `None` when the context is (or becomes) cancelled. Outside any
/// job the context is the root, which is cancelled only when [`cancel_jobs`]
/// is called or `Runtime::run`'s main future fails.
pub async fn cancellable<F: Future>(lua: &Lua, future: F) -> Option<F::Output> {
    let token = match scheduler(lua) {
        Ok(s) => s.current_token(thread_key(lua)),
        Err(_) => return Some(future.await),
    };
    tokio::select! {
        biased;
        () = token.cancelled() => None,
        value = future => Some(value),
    }
}

/// Cancel every root child and standalone supervisor job.
///
/// Hosts call this before returning from `Runtime::run` to shut background
/// jobs down instead of waiting for them.
pub fn cancel_jobs(lua: &Lua) {
    if let Ok(s) = scheduler(lua) {
        s.root().token.cancel();
        for job in s.detached_jobs() {
            job.token.cancel();
        }
    }
}

/// Receives a failure nobody else will see: the error value of a job started
/// with `launch` that failed in a supervisor scope (`supervisor_scope`, a
/// standalone supervisor job, or the implicit root of `Runtime::run`).
/// Cancellation never reaches it.
pub type UnhandledHandler = Rc<dyn Fn(&Lua, Value)>;

/// Replace the handler for unhandled job failures, like kotlinx.coroutines'
/// `CoroutineExceptionHandler`; `None` restores the default, which prints the
/// failure to stderr. Returns the previous handler.
///
/// Test harnesses use it to fail a test instead of printing.
///
/// # Errors
///
/// When `lua` has no runtime installed.
pub fn set_unhandled_handler(
    lua: &Lua,
    handler: Option<UnhandledHandler>,
) -> Result<Option<UnhandledHandler>> {
    Ok(scheduler(lua)?.unhandled.replace(handler))
}

/// Install the scheduler; returns the core table for the prelude.
pub(crate) fn install(lua: &Lua) -> Result<Table> {
    lua.set_app_data(Rc::new(Scheduler::new()));
    core(lua)
}

/// Start a fresh root for one `Runtime::run`.
pub(crate) fn open_root(lua: &Lua) -> Result<Rc<Node>> {
    let s = scheduler(lua)?;
    let root = Node::new(Kind::Root, None, CancellationToken::new(), None);
    *s.root.borrow_mut() = root.clone();
    s.running.set(true);
    Ok(root)
}

/// Wait for the root's children, then stop accepting launches.
pub(crate) async fn close_root(lua: &Lua, root: &Rc<Node>) -> Result<()> {
    root.wait_children().await;
    let s = scheduler(lua)?;
    let detached = s.detached_jobs();
    for job in &detached {
        job.token.cancel();
    }
    for job in detached {
        job.wait_children().await;
        if !job.is_done() {
            complete(lua, &job, Status::Cancelled, Value::Nil);
        }
    }
    s.detached_jobs.borrow_mut().clear();
    s.running.set(false);
    Ok(())
}

fn node(ud: &AnyUserData) -> Result<Rc<Node>> {
    Ok(ud.borrow::<Handle>()?.0.clone())
}

fn handle(lua: &Lua, node: Rc<Node>) -> Result<AnyUserData> {
    lua.create_userdata(Handle(node))
}

fn is_cancellation(lua: &Lua, value: &Value) -> Result<bool> {
    Ok(match value {
        Value::Table(table) => table.to_pointer() == cancelled(lua)?.to_pointer(),
        _ => false,
    })
}

fn spawn(
    lua: &Lua,
    parent: Rc<Node>,
    kind: Kind,
    body: Function,
    coroutine_name: Option<String>,
    lazy: bool,
) -> Result<AnyUserData> {
    let s = scheduler(lua)?;
    if !s.running.get() {
        return Err(mlua::Error::runtime(
            "luastd.async: launching needs Runtime::run (the executor is not running)",
        ));
    }
    let runner = s
        .runner
        .borrow()
        .clone()
        .ok_or_else(|| mlua::Error::runtime("luastd.async: runner not set"))?;
    let child = Node::new(
        kind,
        Some(&parent),
        parent.token.child_token(),
        coroutine_name,
    );
    if lazy {
        child.lazy.set(true);
        child.started.set(false);
    }
    if parent.is_done() {
        // A finished scope cannot own new work (as in kotlinx.coroutines).
        child.token.cancel();
    }
    Node::add_child(&parent, child.clone());

    let thread = lua.create_thread(runner)?;
    let key = thread.to_pointer() as usize;
    s.stacks
        .borrow_mut()
        .insert(key, vec![Entry::Node(child.clone())]);
    let ud = handle(lua, child.clone())?;
    let future = thread.into_async::<()>((ud.clone(), body))?;
    let lua = lua.clone();
    let node_for_wait = child.clone();
    tokio::task::spawn_local(async move {
        // Lazy jobs wait for `start_job` (or cancellation) before running.
        if node_for_wait.lazy.get() && !node_for_wait.started.get() {
            tokio::select! {
                biased;
                () = node_for_wait.token.cancelled() => {}
                () = node_for_wait.start_notify.notified() => {}
            }
            if node_for_wait.token.is_cancelled() && !node_for_wait.started.get() {
                if !node_for_wait.is_done() {
                    complete(&lua, &node_for_wait, Status::Cancelled, Value::Nil);
                }
                s.stacks.borrow_mut().remove(&key);
                return;
            }
        }
        let outcome = future.await;
        if !child.is_done() {
            // The runner settles every job itself; this only guards against
            // an internal error leaving joiners waiting forever.
            let message = match outcome {
                Err(error) => error.to_string(),
                Ok(()) => "job ended without settling".to_owned(),
            };
            let value = lua
                .create_string(&message)
                .map(Value::String)
                .unwrap_or(Value::Nil);
            complete(&lua, &child, Status::Failed, value);
        }
        s.stacks.borrow_mut().remove(&key);
    });
    Ok(ud)
}

/// Wait for children and decide how `node` ended.
async fn settle(lua: &Lua, node: &Rc<Node>, ok: bool, error: Value) -> Result<(Status, Value)> {
    let body_cancelled = !ok && is_cancellation(lua, &error)?;
    if !ok && !body_cancelled {
        node.token.cancel();
    }
    // Unstarted lazy children never run; cancel them so the scope can finish.
    for child in node.children.borrow().clone() {
        if child.lazy.get() && !child.started.get() && !child.is_done() {
            child.token.cancel();
            complete(lua, &child, Status::Cancelled, Value::Nil);
        }
    }
    node.wait_children().await;
    if let Some(timer) = node.timer.borrow_mut().take() {
        timer.abort();
    }
    let child_failure = node.child_failure.borrow().clone();
    Ok(if !ok && !body_cancelled {
        (Status::Failed, error)
    } else if let Some(failure) = child_failure {
        (Status::Failed, failure)
    } else if node.timed_out.get() {
        (Status::Timeout, Value::Nil)
    } else if body_cancelled || node.token.is_cancelled() {
        (Status::Cancelled, Value::Nil)
    } else {
        (Status::Ok, Value::Nil)
    })
}

/// Record the result, tell the parent, and wake joiners.
fn complete(lua: &Lua, node: &Rc<Node>, status: Status, value: Value) {
    if node.is_done() {
        return;
    }
    *node.result.borrow_mut() = Some((status, value.clone()));
    if let Some(parent) = node.parent.as_ref().and_then(Weak::upgrade) {
        Node::remove_child(&parent, node);
        if node.kind.is_job() && status == Status::Failed {
            if !parent.supervisor() {
                parent.child_failure.borrow_mut().get_or_insert(value);
                parent.token.cancel();
            } else if node.kind == Kind::Launch {
                report_unhandled(lua, &value);
            }
        }
    }
    node.done.notify_waiters();
}

fn start_job(lua: &Lua, node: Rc<Node>) -> Result<bool> {
    if node.is_done() {
        return Ok(false);
    }
    if node.token.is_cancelled() {
        if node.lazy.get() && !node.started.get() && !node.is_done() {
            complete(lua, &node, Status::Cancelled, Value::Nil);
        }
        return Ok(false);
    }
    if node.started.get() {
        return Ok(false);
    }
    if !node.lazy.get() {
        return Ok(false);
    }
    node.started.set(true);
    node.start_notify.notify_waiters();
    Ok(true)
}

fn report_unhandled(lua: &Lua, value: &Value) {
    let handler = scheduler(lua)
        .ok()
        .and_then(|s| s.unhandled.borrow().clone());
    if let Some(handler) = handler {
        handler(lua, value.clone());
        return;
    }
    let text = lua
        .coerce_string(value.clone())
        .ok()
        .flatten()
        .map(|s| s.to_string_lossy())
        .or_else(|| {
            let tostring: Function = lua.globals().get("tostring").ok()?;
            tostring.call::<String>(value.clone()).ok()
        })
        .unwrap_or_else(|| format!("{value:?}"));
    eprintln!("luastd.async: unhandled failure in a launched job: {text}");
}

fn kind(name: &str) -> Result<Kind> {
    Ok(match name {
        "launch" => Kind::Launch,
        "async" => Kind::Async,
        "scope" => Kind::Scope,
        "supervisor" => Kind::Supervisor,
        "timeout" => Kind::Timeout,
        other => return Err(mlua::Error::runtime(format!("unknown node kind {other:?}"))),
    })
}

/// Channel state: a bounded queue; `cap == 0` is a rendezvous.
struct ChannelState {
    cap: usize,
    overflow: &'static str,
    queue: RefCell<VecDeque<(u64, Value)>>,
    next_seq: Cell<u64>,
    taken: Cell<u64>,
    waiting_receivers: Cell<usize>,
    closed: Cell<bool>,
    /// The error `close` was called with, if any.
    closed_reason: RefCell<Option<Value>>,
    /// `cancel()`d: closed, buffer dropped, senders are cancelled.
    cancelled: Cell<bool>,
    changed: Notify,
}

#[derive(Clone)]
pub(crate) struct Channel(Rc<ChannelState>);

impl UserData for Channel {}

struct WaitingReceiver(Rc<ChannelState>);

impl Drop for WaitingReceiver {
    fn drop(&mut self) {
        self.0
            .waiting_receivers
            .set(self.0.waiting_receivers.get() - 1);
    }
}

/// Semaphore state: a counting permit pool backed by tokio's fair semaphore.
#[derive(Clone)]
pub(crate) struct Semaphore(Rc<SemaphoreState>);

pub(crate) struct SemaphoreState {
    max: usize,
    inner: std::sync::Arc<tokio::sync::Semaphore>,
}

impl Semaphore {
    pub(crate) fn new(permits: usize, acquired: usize) -> Result<Self> {
        if permits == 0 {
            return Err(crate::errors::LuaError::new(
                "InvalidArgument",
                "semaphore needs at least 1 permit",
            )
            .into());
        }
        if acquired > permits {
            return Err(crate::errors::LuaError::new(
                "InvalidArgument",
                "acquiredPermits out of range",
            )
            .into());
        }
        let inner = std::sync::Arc::new(tokio::sync::Semaphore::new(permits));
        for _ in 0..acquired {
            let permit = inner.try_acquire().map_err(|_| {
                mlua::Error::from(crate::errors::LuaError::new(
                    "InvalidArgument",
                    "acquiredPermits out of range",
                ))
            })?;
            std::mem::forget(permit);
        }
        Ok(Self(Rc::new(SemaphoreState {
            max: permits,
            inner,
        })))
    }
}

impl UserData for Semaphore {}

impl Channel {
    fn new(cap: usize, overflow: &'static str) -> Self {
        Self(Rc::new(ChannelState {
            cap,
            overflow,
            queue: RefCell::default(),
            next_seq: Cell::new(0),
            taken: Cell::new(0),
            waiting_receivers: Cell::new(0),
            closed: Cell::new(false),
            closed_reason: RefCell::default(),
            cancelled: Cell::new(false),
            changed: Notify::new(),
        }))
    }

    /// `"ok"`, `"full"` or `"closed"`; never waits for room.
    fn try_send(&self, value: Value) -> &'static str {
        let state = &self.0;
        if state.cancelled.get() || state.closed.get() {
            return "closed";
        }
        if state.cap == 0 && state.overflow == "suspend" && state.waiting_receivers.get() == 0 {
            return "full";
        }
        let len = state.queue.borrow().len();
        if len < state.cap.max(1) {
            let seq = state.next_seq.get();
            state.next_seq.set(seq + 1);
            state.queue.borrow_mut().push_back((seq, value));
            state.changed.notify_waiters();
            "ok"
        } else if state.overflow == "drop_latest" {
            let seq = state.next_seq.get();
            state.next_seq.set(seq + 1);
            state.queue.borrow_mut().push_back((seq, value));
            state.queue.borrow_mut().pop_back();
            state.changed.notify_waiters();
            "ok"
        } else if matches!(state.overflow, "conflated" | "drop_oldest") {
            let seq = state.next_seq.get();
            state.next_seq.set(seq + 1);
            state.queue.borrow_mut().push_back((seq, value));
            state.queue.borrow_mut().pop_front();
            state.changed.notify_waiters();
            "ok"
        } else {
            "full"
        }
    }

    fn try_receive(&self) -> (&'static str, Value) {
        let state = &self.0;
        if state.cancelled.get() {
            return ("cancelled", Value::Nil);
        }
        if let Some((seq, value)) = state.queue.borrow_mut().pop_front() {
            state.taken.set(state.taken.get().max(seq + 1));
            state.changed.notify_waiters();
            return ("value", value);
        }
        if state.closed.get() {
            ("closed", Value::Nil)
        } else {
            ("empty", Value::Nil)
        }
    }

    /// `"ok"`, `"closed"`, `"cancelled"` (the caller was) or
    /// `"channel_cancelled"` (the channel was).
    async fn send(&self, lua: &Lua, value: Value) -> &'static str {
        let state = &self.0;
        let wait_for_room = async {
            loop {
                let notified = state.changed.notified();
                if state.cancelled.get() {
                    return Some(None);
                }
                if state.closed.get() {
                    return None;
                }
                let len = state.queue.borrow().len();
                if len < state.cap.max(1) {
                    let seq = state.next_seq.get();
                    state.next_seq.set(seq + 1);
                    state.queue.borrow_mut().push_back((seq, value));
                    state.changed.notify_waiters();
                    return Some(Some(seq));
                }
                if state.overflow == "drop_latest" {
                    let seq = state.next_seq.get();
                    state.next_seq.set(seq + 1);
                    state.queue.borrow_mut().push_back((seq, value));
                    state.queue.borrow_mut().pop_back();
                    state.changed.notify_waiters();
                    return Some(Some(seq));
                }
                if matches!(state.overflow, "conflated" | "drop_oldest") {
                    let seq = state.next_seq.get();
                    state.next_seq.set(seq + 1);
                    state.queue.borrow_mut().push_back((seq, value));
                    state.queue.borrow_mut().pop_front();
                    state.changed.notify_waiters();
                    return Some(Some(seq));
                }
                notified.await;
            }
        };
        let seq = match cancellable(lua, wait_for_room).await {
            None => return "cancelled",
            Some(None) => return "closed",
            Some(Some(None)) => return "channel_cancelled",
            Some(Some(Some(seq))) => seq,
        };
        if state.cap > 0 {
            return "ok";
        }
        if state.overflow != "suspend" {
            return "ok";
        }
        // Rendezvous: wait until a receiver took this value.
        let taken = async {
            loop {
                let notified = state.changed.notified();
                if state.taken.get() > seq {
                    return true;
                }
                if state.cancelled.get() {
                    return false;
                }
                notified.await;
            }
        };
        match cancellable(lua, taken).await {
            Some(true) => "ok",
            Some(false) => "channel_cancelled",
            None => {
                state.queue.borrow_mut().retain(|(s, _)| *s != seq);
                state.changed.notify_waiters();
                "cancelled"
            }
        }
    }

    /// `("value", v)`, `("closed")`, `("timeout")` or `("cancelled")`.
    async fn receive(&self, lua: &Lua, timeout: Option<Duration>) -> (&'static str, Value) {
        let state = &self.0;
        let next = async {
            loop {
                let notified = state.changed.notified();
                let item = state.queue.borrow_mut().pop_front();
                if let Some((seq, value)) = item {
                    state.taken.set(state.taken.get().max(seq + 1));
                    state.changed.notify_waiters();
                    return Some(value);
                }
                if state.closed.get() {
                    return None;
                }
                state
                    .waiting_receivers
                    .set(state.waiting_receivers.get() + 1);
                let waiting_receiver = WaitingReceiver(state.clone());
                notified.await;
                drop(waiting_receiver);
            }
        };
        let raced = async {
            match timeout {
                Some(after) => tokio::time::timeout(after, next).await.ok(),
                None => Some(next.await),
            }
        };
        match cancellable(lua, raced).await {
            None => ("cancelled", Value::Nil),
            Some(None) => ("timeout", Value::Nil),
            Some(Some(None)) => ("closed", Value::Nil),
            Some(Some(Some(value))) => ("value", value),
        }
    }

    fn close(&self, reason: Option<Value>) {
        if self.0.closed.get() {
            return;
        }
        if let Some(reason) = reason {
            *self.0.closed_reason.borrow_mut() = Some(reason);
        }
        self.0.closed.set(true);
        self.0.changed.notify_waiters();
    }

    fn cancel(&self) {
        self.0.cancelled.set(true);
        self.0.closed.set(true);
        self.0.queue.borrow_mut().clear();
        self.0.changed.notify_waiters();
    }
}

/// `ms` as a `Duration`; huge or infinite values saturate instead of
/// panicking, and tokio treats a deadline past its range as "never".
fn duration(ms: f64) -> Duration {
    Duration::try_from_secs_f64(ms.max(0.0) / 1000.0).unwrap_or(Duration::MAX)
}

fn core(lua: &Lua) -> Result<Table> {
    let core = lua.create_table()?;
    core.set("CANCELLED", cancelled(lua)?)?;

    core.set(
        "set_runner",
        lua.create_function(|lua, runner: Function| {
            *scheduler(lua)?.runner.borrow_mut() = Some(runner);
            Ok(())
        })?,
    )?;
    core.set(
        "new_error",
        lua.create_function(|lua, (kind, message): (String, String)| {
            crate::errors::LuaError::new(kind, message).table(lua)
        })?,
    )?;
    core.set(
        "current",
        lua.create_function(|lua, ()| {
            let s = scheduler(lua)?;
            handle(lua, s.current_node(thread_key(lua)))
        })?,
    )?;
    core.set(
        "active",
        lua.create_function(|lua, ()| {
            let s = scheduler(lua)?;
            Ok(!s.current_token(thread_key(lua)).is_cancelled())
        })?,
    )?;
    core.set(
        "spawn",
        lua.create_function(
            |lua,
             (parent, name, body, coroutine_name, lazy): (
                AnyUserData,
                String,
                Function,
                Option<String>,
                Option<bool>,
            )| {
                spawn(
                    lua,
                    node(&parent)?,
                    kind(&name)?,
                    body,
                    coroutine_name,
                    lazy.unwrap_or(false),
                )
            },
        )?,
    )?;
    core.set(
        "spawn_lazy",
        lua.create_function(
            |lua,
             (parent, name, body, coroutine_name): (
                AnyUserData,
                String,
                Function,
                Option<String>,
            )| {
                spawn(
                    lua,
                    node(&parent)?,
                    kind(&name)?,
                    body,
                    coroutine_name,
                    true,
                )
            },
        )?,
    )?;
    core.set(
        "start_job",
        lua.create_function(|lua, ud: AnyUserData| start_job(lua, node(&ud)?))?,
    )?;
    core.set(
        "supervisor_job",
        lua.create_function(|lua, ()| {
            let s = scheduler(lua)?;
            let job = Node::new(Kind::Supervisor, None, CancellationToken::new(), None);
            s.detached_jobs.borrow_mut().push(job.clone());
            handle(lua, job)
        })?,
    )?;
    core.set(
        "enter",
        lua.create_function(
            |lua, (name, coroutine_name, parent): (String, Option<String>, Option<AnyUserData>)| {
                let s = scheduler(lua)?;
                let key = thread_key(lua);
                let parent = parent.map(|parent| node(&parent)).transpose()?;
                let (parent, token) = match parent {
                    Some(parent) => (parent.clone(), parent.token.child_token()),
                    None => (s.current_node(key), s.current_token(key).child_token()),
                };
                let scope = Node::new(kind(&name)?, Some(&parent), token, coroutine_name);
                if parent.is_done() {
                    scope.token.cancel();
                }
                Node::add_child(&parent, scope.clone());
                s.push(key, Entry::Node(scope.clone()));
                handle(lua, scope)
            },
        )?,
    )?;
    core.set(
        "coroutine_name",
        lua.create_function(|_, ud: AnyUserData| Ok(node(&ud)?.coroutine_name.clone()))?,
    )?;
    core.set(
        "timeout",
        lua.create_function(|lua, (ud, ms): (AnyUserData, f64)| {
            let scope = node(&ud)?;
            if !scheduler(lua)?.running.get() {
                return Err(mlua::Error::runtime(
                    "luastd.async: with_timeout needs Runtime::run",
                ));
            }
            let weak = Rc::downgrade(&scope);
            let timer = tokio::task::spawn_local(async move {
                tokio::time::sleep(duration(ms)).await;
                if let Some(scope) = weak.upgrade() {
                    scope.timed_out.set(true);
                    scope.token.cancel();
                }
            });
            *scope.timer.borrow_mut() = Some(timer);
            Ok(())
        })?,
    )?;
    core.set(
        "settle",
        lua.create_async_function(
            |lua, (ud, ok, error): (AnyUserData, bool, Value)| async move {
                let node = node(&ud)?;
                let (status, value) = settle(&lua, &node, ok, error).await?;
                Ok((status.as_str(), value))
            },
        )?,
    )?;
    core.set(
        "complete",
        lua.create_function(|lua, (ud, status, value): (AnyUserData, String, Value)| {
            let node = node(&ud)?;
            if !node.kind.is_job() {
                scheduler(lua)?.pop(thread_key(lua));
            }
            complete(lua, &node, Status::parse(&status)?, value);
            Ok(())
        })?,
    )?;
    core.set(
        "join",
        lua.create_async_function(|lua, ud: AnyUserData| async move {
            let node = node(&ud)?;
            Ok(cancellable(&lua, node.wait_done()).await.is_some())
        })?,
    )?;
    core.set(
        "result",
        lua.create_function(|_, ud: AnyUserData| {
            let node = node(&ud)?;
            let result = node.result.borrow().clone();
            Ok(match result {
                Some((status, value)) => (Some(status.as_str()), value),
                None => (None, Value::Nil),
            })
        })?,
    )?;
    core.set(
        "cancel",
        lua.create_function(|lua, ud: AnyUserData| {
            let target = node(&ud)?;
            target.token.cancel();
            if target.lazy.get() && !target.started.get() && !target.is_done() {
                complete(lua, &target, Status::Cancelled, Value::Nil);
            }
            if target.kind == Kind::Supervisor && target.parent.is_none() {
                if target.children.borrow().is_empty() {
                    complete(lua, &target, Status::Cancelled, Value::Nil);
                } else if scheduler(lua)?.running.get() {
                    let lua = lua.clone();
                    tokio::task::spawn_local(async move {
                        target.wait_children().await;
                        if !target.is_done() {
                            complete(&lua, &target, Status::Cancelled, Value::Nil);
                        }
                    });
                }
            }
            Ok(())
        })?,
    )?;
    core.set(
        "cancel_current",
        lua.create_function(|lua, ()| {
            // Never the root: outside any job the error alone unwinds.
            let node = scheduler(lua)?.current_node(thread_key(lua));
            if node.kind != Kind::Root {
                node.token.cancel();
            }
            Ok(())
        })?,
    )?;
    core.set(
        "state",
        lua.create_function(|_, ud: AnyUserData| {
            let node = node(&ud)?;
            let status_cancelled =
                matches!(node.result.borrow().as_ref(), Some((Status::Cancelled, _)));
            let cancelled = node.token.is_cancelled() || status_cancelled;
            Ok((
                !node.is_done() && !cancelled && node.started.get(),
                cancelled,
                node.is_done(),
            ))
        })?,
    )?;
    core.set(
        "on_cancel",
        lua.create_function(|_, (ud, handler): (AnyUserData, Function)| {
            node(&ud)?.on_cancel.borrow_mut().push(handler);
            Ok(())
        })?,
    )?;
    core.set(
        "take_on_cancel",
        lua.create_function(|lua, ud: AnyUserData| {
            let handlers = std::mem::take(&mut *node(&ud)?.on_cancel.borrow_mut());
            lua.create_sequence_from(handlers.into_iter().rev())
        })?,
    )?;
    core.set(
        "push_non_cancellable",
        lua.create_function(|lua, ()| {
            scheduler(lua)?.push(thread_key(lua), Entry::NonCancellable);
            Ok(())
        })?,
    )?;
    core.set(
        "pop_non_cancellable",
        lua.create_function(|lua, ()| {
            scheduler(lua)?.pop(thread_key(lua));
            Ok(())
        })?,
    )?;
    core.set(
        "delay",
        lua.create_async_function(|lua, ms: f64| async move {
            Ok(cancellable(&lua, tokio::time::sleep(duration(ms)))
                .await
                .is_some())
        })?,
    )?;
    core.set(
        "yield",
        lua.create_async_function(|lua, ()| async move {
            Ok(cancellable(&lua, tokio::task::yield_now()).await.is_some())
        })?,
    )?;
    core.set(
        "now_ms",
        lua.create_function(|lua, ()| Ok(scheduler(lua)?.epoch.elapsed().as_secs_f64() * 1000.0))?,
    )?;

    core.set(
        "channel",
        lua.create_function(|_, (cap, overflow): (usize, String)| {
            let overflow: &'static str = match overflow.as_str() {
                "drop_oldest" => "drop_oldest",
                "drop_latest" => "drop_latest",
                "conflated" => "conflated",
                _ => "suspend",
            };
            Ok(Channel::new(cap, overflow))
        })?,
    )?;
    core.set(
        "send",
        lua.create_async_function(|lua, (ch, value): (UserDataRef<Channel>, Value)| {
            let ch = ch.clone();
            async move { Ok(ch.send(&lua, value).await) }
        })?,
    )?;
    core.set(
        "try_send",
        lua.create_function(
            |_, (ch, value): (UserDataRef<Channel>, Value)| Ok(ch.try_send(value)),
        )?,
    )?;
    core.set(
        "try_receive",
        lua.create_function(|lua, ch: UserDataRef<Channel>| {
            let (status, value) = ch.try_receive();
            let reason = if status == "closed" {
                ch.0.closed_reason.borrow().clone().unwrap_or(Value::Nil)
            } else {
                Value::Nil
            };
            Ok(MultiValue::from_vec(vec![
                Value::String(lua.create_string(status)?),
                value,
                reason,
            ]))
        })?,
    )?;
    core.set(
        "close_reason",
        lua.create_function(|_, ch: UserDataRef<Channel>| {
            Ok(ch.0.closed_reason.borrow().clone().unwrap_or(Value::Nil))
        })?,
    )?;
    core.set(
        "receive",
        lua.create_async_function(|lua, (ch, timeout): (UserDataRef<Channel>, Option<f64>)| {
            let ch = ch.clone();
            async move {
                let (status, value) = ch.receive(&lua, timeout.map(duration)).await;
                let reason = if status == "closed" {
                    ch.0.closed_reason.borrow().clone().unwrap_or(Value::Nil)
                } else {
                    Value::Nil
                };
                Ok(MultiValue::from_vec(vec![
                    Value::String(lua.create_string(status)?),
                    value,
                    reason,
                ]))
            }
        })?,
    )?;
    core.set(
        "close",
        lua.create_function(|_, (ch, reason): (UserDataRef<Channel>, Option<Value>)| {
            ch.close(reason);
            Ok(())
        })?,
    )?;
    core.set(
        "cancel_channel",
        lua.create_function(|_, ch: UserDataRef<Channel>| {
            ch.cancel();
            Ok(())
        })?,
    )?;
    core.set(
        "is_closed",
        lua.create_function(|_, ch: UserDataRef<Channel>| Ok(ch.0.closed.get()))?,
    )?;
    core.set(
        "is_closed_for_receive",
        lua.create_function(|_, ch: UserDataRef<Channel>| {
            Ok(ch.0.closed.get() && ch.0.queue.borrow().is_empty())
        })?,
    )?;
    core.set(
        "is_empty",
        lua.create_function(|_, ch: UserDataRef<Channel>| {
            Ok(!ch.0.closed.get() && ch.0.queue.borrow().is_empty())
        })?,
    )?;
    core.set(
        "semaphore",
        lua.create_function(|_, (permits, acquired): (usize, Option<usize>)| {
            Semaphore::new(permits, acquired.unwrap_or(0))
        })?,
    )?;
    core.set(
        "acquire",
        lua.create_async_function(|lua, sem: UserDataRef<Semaphore>| {
            let sem = sem.clone();
            async move {
                let permit = sem.0.inner.clone().acquire_owned();
                match cancellable(&lua, permit).await {
                    Some(Ok(permit)) => {
                        std::mem::forget(permit);
                        Ok(())
                    }
                    Some(Err(_)) => Err(mlua::Error::runtime("semaphore closed")),
                    None => Err(crate::errors::LuaError::cancelled().into()),
                }
            }
        })?,
    )?;
    core.set(
        "release",
        lua.create_function(|_, sem: UserDataRef<Semaphore>| {
            let state = &sem.0;
            if state.inner.available_permits() >= state.max {
                return Err(crate::errors::LuaError::new(
                    "IllegalState",
                    "The number of released permits cannot be greater than the number of permits",
                )
                .into());
            }
            state.inner.add_permits(1);
            Ok(())
        })?,
    )?;
    core.set(
        "try_acquire",
        lua.create_function(
            |_, sem: UserDataRef<Semaphore>| match sem.0.inner.try_acquire() {
                Ok(permit) => {
                    std::mem::forget(permit);
                    Ok(true)
                }
                Err(_) => Ok(false),
            },
        )?,
    )?;
    core.set(
        "available_permits",
        lua.create_function(|_, sem: UserDataRef<Semaphore>| Ok(sem.0.inner.available_permits()))?,
    )?;
    Ok(core)
}
