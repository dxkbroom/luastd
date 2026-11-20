# luastd

A Lua standard library written in Rust, plus a runtime that embeds it with
permission-checked IO and structured async.

## Language

### Runtime

**Host**:
The Rust application that embeds `luastd_runtime` and chooses the Lua version,
vendoring, effect modules and permissions.
_Avoid_: App, embedder

**Pure module**:
A data-only module (no IO) that every runtime installs; together they form the floor.
_Avoid_: Core module, safe module

**Floor**:
The set of pure modules a host cannot opt out of.
_Avoid_: Baseline, prelude

**Effect module**:
A module that performs IO (`luastd.fs`, `luastd.env`, `luastd.process`) and can only
be installed with a `PermissionsContainer`.
_Avoid_: IO module, unsafe module

**Prompter**:
The host's async answer to a permission the `PermissionsContainer` has not
decided yet; its answer is recorded in the container (ADR 0004).
_Avoid_: Permission dialog, asker

**Env overlay**:
The runtime's own view of environment variables: `luastd.env.set` and `unset`
change it, reads fall through to the process environment, and the process
environment itself is never modified.
_Avoid_: Fake env, env cache

**Structured error**:
A `luastd.Error` table raised by luastd with `kind`, `message`, an optional
`cause` and context fields such as `permission` and `target`; `tostring` gives
`"<kind>: <message>"`. It keeps its identity through Rust frames (ADR 0006).
_Avoid_: Error string, exception

### Async

**Scope**:
A structured-concurrency boundary that owns its child coroutines; it completes when
all children complete and cancelling it cancels them.
_Avoid_: Context, group, nursery

**Supervisor scope**:
A scope where a failing child does not cancel its siblings or parent; each plugin
runs inside one.
_Avoid_: Plugin sandbox, isolate

**Job**:
A coroutine lifetime handle that can be joined or cancelled and can own child
coroutines.
_Avoid_: Task, thread, fiber

**Supervisor job**:
A Job whose child failures do not cancel the job or its other children; it stays
active until cancelled.
_Avoid_: Supervisor scope

**Coroutine context**:
The set of keyed elements carried by a coroutine, including its Job and optional
execution metadata such as its name.
_Avoid_: Coroutine options

**Deferred**:
A Job that also produces a value, obtained with `await`.
_Avoid_: Promise, future

**Root scope**:
The supervisor scope `Runtime::run` opens around the host's main future; jobs
launched outside any other scope belong to it.
_Avoid_: Global scope, main job

**Cancellation point**:
A suspension, such as `delay`, `join`, `receive` or a permission prompt, where a
cancelled coroutine receives the cancellation error.
_Avoid_: Checkpoint, yield point

**Channel**:
A hot stream between coroutines where `send` and `receive` suspend; values are
produced whether or not anyone collects them.
_Avoid_: Queue, pipe, event bus

**Flow**:
A cold stream that runs its producer only when collected, with operators such as
`map`, `filter` and `collect`. Not built yet; tracked in [#1](https://github.com/dxkbroom/luastd/issues/1).
_Avoid_: Observable, stream, iterator

### API

**Canonical form**:
The one spelling of an operation that docs and examples use; any other form must
compose differently (ADR 0007).
_Avoid_: Preferred alias, main name

**Prefix form**:
A module function that does what a method does, taking the receiver first, so
it can be passed as a value. `async.await(d)` and `async.join(job)` have no
method twin (ADR 0008).
_Avoid_: Static form, free function

### tinyvi example

**Plugin**:
A Lua module that returns a setup `function(plugin)`; `tinyvi` calls it inside a
fresh supervisor scope and cancels that scope to unload it.
_Avoid_: Extension, addon, script
