# Async runtime roadmap (draft)

Status: draft, 2026-11-21. Living document — reorder as priorities shift.
Companion to `PLAN.md` (layers 6–8) and the kotlinx.coroutines port report.

This is **not** a defer list. Items here are features we intend to build; the
Kotlin port status (`defer`/`not-applicable`) is bookkeeping until they land.

## Guiding principles

- One canonical form per operation (ADR 0007): add a feature only when it
  composes differently from what already exists.
- Each feature ships with: an ADR if it changes cancellation/error semantics,
  EmmyLua stubs, Rust tests, and (where applicable) Kotlin port conversions.
- Async is the blessed path (ADR 0008): every new primitive gets an async
  form first, `*_sync`/`try_*` variants as the rule requires.
- Nothing here is a permanent non-goal. Items previously listed as non-goals
  (cold `Flow`) are treated as large, on-demand work rather than exclusions.

## Current state (what already works)

- Scopes: `async.scope`, `async.try_scope`, `async.supervisor_scope`,
  `async.with_timeout`.
- Jobs/deferreds: `async.launch`, `async.async`, `async.join`, `async.await`,
  `async.try_await`, `async.await_all`, `async.join_all`.
- Channels: `async.channel(cap)`, send/receive/close/iter/each, `produce`,
  `debounce` (channel + function), `throttle`.
- Context: `async.coroutine_name`, `async.context`, `async.with_context`,
  `async.current_context`, `async.current`.
- Cleanup/cancellation: `async.finally`, `Scope:on_cancel`, `Job:cancel`,
  `Job:on_cancel`, `async.is_active`, `async.is_cancellation`, cancellation-
  aware `pcall`/`xpcall` (ADR 0005).
- I/O effect modules (in progress): `luastd.env` (done), `luastd.fs`,
  `luastd.process` (planned).

## Feature backlog (priority order)

### 1. `CompletableDeferred` — externally completed deferreds

**What it is.** A `Deferred` whose result is supplied from the outside instead
of computed by a coroutine body. In Kotlin:

```kotlin
val d = CompletableDeferred<Int>()
launch { d.complete(42) }   // or d.completeExceptionally(e), d.cancel()
val v = d.await()          // 42
```

**Role in Kotlin.** Bridges callback/async-boundary code into structured
concurrency: a network callback, a UI event, or a host notification can
complete a deferred that some coroutine is awaiting. Also the building block
for `async { ... }` results that are produced by non-coroutine code.

**Role in luastd.** Today every deferred is `async.async(fn)` — the result
comes from a body. There is no way to hand a result in from a Rust host
callback, a channel consumer, or a timer. `CompletableDeferred` fills that
gap and is the smallest addition that unlocks a large slice of the ported
Kotlin tests (`CompletableDeferredTest`, `CompletableJobTest`, and deferred
cases in `AwaitTest`/`AsyncTest`/`ParentCancellationTest`).

**Real-world use cases.**

- Wrapping a host callback into something awaitable:

  ```lua
  local d = async.completable_deferred()
  host:on_response(function (payload) d:complete(payload) end)
  local payload = async.await(d)   -- suspends until the host calls back
  ```

- A one-shot result produced by whichever of several workers finishes first:

  ```lua
  local winner = async.completable_deferred()
  for _, worker in ipairs(workers) do
      async.launch(function () winner:complete(worker:run()) end)
  end
  local result = async.await(winner)
  ```

- Propagating a failure without a coroutine:

  ```lua
  local d = async.completable_deferred()
  if not ok then d:complete_exceptionally(err) end
  ```

**Sketch of the API.**

```lua
local d = async.completable_deferred()            -- Deferred<T>
d:complete(value)                                 -- idempotent-ish: first wins
d:complete_exceptionally(err)
d:cancel(cause?)                                  -- cancels the deferred
-- await/try_await work exactly as for async.async deferreds
```

**Completion semantics (decided).** "First writer wins" (Kotlin): `complete`
returns false on duplicate and does not raise. `complete` always runs on the
Lua thread (ADR 0002); a host thread requests completion by queueing onto the
runtime loop (ergonomics open question remains).

### 2. Lazy jobs (`CoroutineStart.LAZY` + `start()`)

**What it is.** A job/deferred that is created in a `New` state and does not
run until something calls `job:start()` (or it is awaited/joined, which
implicitly starts it). Kotlin:

```kotlin
val job = launch(start = CoroutineStart.LAZY) { work() }
assertFalse(job.isActive)
job.start()
assertTrue(job.isActive)
```

**Role in Kotlin.** Lets you build a graph of work up front and start it on
demand; also the state machine that `JobStatesTest` exercises end to end.

**Role in luastd.** Today `launch`/`async` start immediately. Adding a lazy
variant (`async.launch_lazy(fn)`, `async.async_lazy(fn)`, plus `job:start()`)
exercises the existing job-state transitions (New → Active → Completing →
Completed/Cancelled) that are currently only partially covered, and unlocks
`AsyncLazyTest`, `LaunchLazyTest`, `JobStatesTest`.

**Real-world use cases.**

- Deferred computation that may never be needed:

  ```lua
  local report = async.async_lazy(function () return expensive_report() end)
  if user_wants_report then return async.await(report) end   -- only runs if needed
  ```

- Building a pipeline where stages start on demand:

  ```lua
  local stage1 = async.launch_lazy(function () ingest() end)
  local stage2 = async.launch_lazy(function () transform() end)
  stage1:start(); stage2:start()   -- explicit kick-off
  ```

### 3. Dispatchers (Unconfined / Default)

**What it is.** A `CoroutineContext` element that decides which thread/loop a
coroutine resumes on. `Dispatchers.Unconfined` runs on the caller's thread
until the first suspension; `Dispatchers.Default` uses a shared pool.

**Role in Kotlin.** The mechanism behind `withContext(Dispatchers.IO) { ... }`,
`launch(Dispatchers.Default)`, and the unconfined tests that assert immediate
execution semantics.

**Role in luastd / feasibility.** A *full* dispatcher abstraction with thread
pools is **not achievable** on top of mlua regardless of ADR 0002: a Lua
state is `!Send` and Lua's C API is not thread-safe for one state, so no
pool can run Lua code. ADR 0002 records this rather than imposing it. What
remains possible is scheduling-order control on the single thread, which is
already how the executor (ADR 0003) works. Therefore the dispatcher-dependent
Kotlin tests (`Unconfined*`, dispatcher cases in `WithContextTest`,
`ScopedBuildersCancelledStartTest`, `JobExtensionsTest`,
`ImmediateYieldTest`) are **not-applicable** ("single-threaded runtime; no
dispatcher pool possible"), not deferred. `with_context` stays for
context-element swapping. No dispatcher backlog item.

**Real-world use cases.**

- Immediate, non-suspending work that should not hop to the executor:

  ```lua
  async.launch(async.coroutine_name("init"), function ()
      -- runs synchronously up to the first delay/yield
      setup()
      async.delay(0)   -- now yields
  end)
  ```

- `with_context` to override context elements for a block:

  ```lua
  async.with_context(async.context(async.coroutine_name("worker")), function ()
      assert.is_equal("worker", async.current_context():coroutine_name():name)
  end)
  ```

**Open questions.** Whether to model dispatchers at all given ADR 0002, or
just expose `Unconfined` semantics as the default and skip the abstraction.
Recommendation: expose `Unconfined` semantics only; do not build a thread pool.

### 4. `NonCancellable` + `CoroutineStart.ATOMIC` / `UNDISPATCHED`

**What it is.** `NonCancellable` is a `Job` that is never cancelled, used as a
parent so a child keeps running after the parent is cancelled. `ATOMIC` makes
a launched coroutine non-cancellable until its first suspension. `UNDISPATCHED`
starts the coroutine immediately on the caller's thread.

**Role in Kotlin.** Cancellation-control primitives: `withContext(NonCancellable) { cleanup }`,
atomic cancellation tests, undispatched entry.

**Role in luastd.** luastd has no dispatchers, so `UNDISPATCHED` is mostly
"run on current thread" (overlaps with Unconfined). `NonCancellable` and
`ATOMIC` are cancellation-semantics features that several `AsyncTest` cases
defer on. Implementing them hardens the cancellation model.

**Real-world use case.**

```lua
-- cleanup that must run even if the scope is cancelled
async.scope(function (scope)
    scope:on_cancel(function ()
        async.with_context(async.context(async.supervisor_job()), function ()
            -- NonCancellable-ish cleanup
            flush_buffers()
        end)
    end)
end)
```

### 5. `CancellableContinuation` (suspend/resume)

**What it is.** The low-level primitive behind `suspendCancellableCoroutine`:
a coroutine can suspend and be resumed later by an external caller, with
cancellation wired through.

**Role in Kotlin.** Building custom suspending functions and callback bridges
with cancellation propagation.

**Role in luastd.** High effort; mostly valuable for host interop. Defer until
a concrete consumer (e.g. a host API) needs it. Unlocks `CancellableContinuation*`
and `CancellableResume*` tests.

### 6. `Mutex` and `Semaphore` ✅ done

**What it is.** Concurrency primitives: `Mutex` (mutual exclusion) and
`Semaphore` (counting permit). Kotlin:

```kotlin
val mutex = Mutex()
mutex.withLock { critical_section() }
val sem = Semaphore(2)
sem.withPermit { ... }
```

**Role in Kotlin.** Protecting shared state across coroutines; limiting
parallelism.

**Feasibility.** Possible and valuable, even on a single thread: a `Mutex`
serializes coroutine access to shared state across yield points (lock suspends
until available), and a `Semaphore` limits concurrency of async work. No
threading required — implemented as a waiter queue + state, like a channel.
Rust primitives give cancellation-aware wait queues; a pure-Lua-over-channels
version is a legitimate v1 shortcut. Unlocks `MutexTest`, `SemaphoreTest`.

**Real-world use cases.**

- Serializing access to a shared resource:

  ```lua
  local m = async.mutex()
  local function update_shared()
      m:with_lock(function () shared.counter = shared.counter + 1 end)
  end
  ```

- Limiting concurrency of outbound requests:

  ```lua
  local sem = async.semaphore(4)
  for _, url in ipairs(urls) do
      async.launch(function ()
          sem:with_permit(function () fetch(url) end)
      end)
  end
  ```

### 7. `Select` (multi-channel await)

**What it is.** `select { ch1.onReceive { ... }; ch2.onReceive { ... } }` —
waits on several channels and runs the branch for whichever fires first.

**Role in Kotlin.** Racing multiple channels/timeouts in one expression.

**Role in luastd.** High effort (needs a multi-waiter primitive). Unlocks
`Select*` tests. Defer until a consumer needs it.

### 8. Cold `Flow` (large, on-demand)

The biggest single item (~60 test classes: operators, `SharedFlow`,
`StateFlow`, `StateIn`, `ShareIn`). Not scheduled as a non-goal; treat as
large, on-demand work driven by a real consumer. Design as its own track
with an ADR before starting; the operator-chain DSL (`flow:map(f):filter(...)`)
is a substantial API surface.

## Sequencing relative to I/O work

Recommendation: finish `luastd.fs` + `luastd.process` (in progress) first,
then run the async feature track in priority order above. Rationale: I/O
modules exercise cancellation/backpressure/channel-streaming in ways the
Kotlin ports cannot, and unblock the example. Async feature work then
benefits from a validated runtime.

## Open questions

- `CompletableDeferred` completion: **first writer wins** (Kotlin semantics),
  `complete` returns false on duplicate. Decided.
- Dispatchers: **not-applicable** (single-threaded runtime; no pool possible).
  Decided — see feature 3.
- `Mutex`/`Semaphore`: Rust primitives with cancellation-aware wait queues
  (preferred) vs pure-Lua-over-channels shortcut for v1. Open.
- Cold `Flow`: large, on-demand; not a non-goal. Design as its own track
  with an ADR when a consumer asks. Decided — see feature 8.
