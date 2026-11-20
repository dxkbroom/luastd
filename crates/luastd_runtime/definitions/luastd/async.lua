---@meta luastd.async

--- Structured concurrency, after kotlinx.coroutines.
---
--- Every coroutine runs inside a scope. A scope completes only when its
--- children have, and cancelling it cancels them. Jobs launched without an
--- explicit context Job belong to the implicit root scope of `Runtime::run`.
--- Standalone supervisor jobs are cancelled when that runtime run ends.
---
--- Cancellation is cooperative: it is delivered at suspension points
--- (`delay`, `join`, `await`, `send`, `receive`, permission prompts, ...) as an
--- error that the runtime's `pcall` and `xpcall` rethrow instead of catching
--- (ADR 0005). Use `async.finally` or `scope:on_cancel` for cleanup.
---@class luastd.async
local async = {}

--- Error raised by `with_timeout` when the time runs out; catchable.
---@class luastd.TimeoutError: luastd.Error
---@field kind "Timeout"

--- Error raised by `async.await` when the job was cancelled; catchable.
---@class luastd.JobCancelledError: luastd.Error
---@field kind "JobCancelled"

--- Error raised by `Channel:send` on a closed channel, and by
--- `Channel:receive` on a closed, empty one.
---@class luastd.ChannelClosedError: luastd.Error
---@field kind "ChannelClosed"

--- A structured-concurrency boundary; passed to scope and job bodies.
---@class luastd.async.Scope
local Scope = {}

--- The coroutine context visible to code running in this scope. Its Job is
--- this scope's lifetime handle; other elements describe execution metadata.
---@return luastd.async.CoroutineContext
function Scope:coroutine_context() end

--- Launch a child job in this scope, whichever coroutine calls it. A context
--- Job replaces this scope as the parent; other elements override metadata.
---@overload fun(context: luastd.async.CoroutineContext, body: async fun(scope: luastd.async.Scope)): luastd.async.Job
---@param context_or_body luastd.async.CoroutineContext | async fun(scope: luastd.async.Scope)
---@param body?           async fun(scope: luastd.async.Scope)
---@return luastd.async.Job
function Scope:launch(context_or_body, body) end

--- Start a child job in this scope that produces values.
---@generic T...
---@param body fun(scope: luastd.async.Scope): T...
---@return luastd.async.Deferred<T...>
function Scope:async(body) end

--- Cancel this scope and its children.
function Scope:cancel() end

--- Whether this scope is neither completed nor cancelled.
---@return boolean
function Scope:is_active() end

--- Whether this scope was cancelled.
---@return boolean
function Scope:is_cancelled() end

--- Whether this scope and its children have finished.
---@return boolean
function Scope:is_completed() end

--- Run `handler` when this scope ends without completing normally (cancelled,
--- timed out or failed). Handlers run last-registered first, cannot be
--- cancelled, and their errors are ignored.
---@param handler fun()
function Scope:on_cancel(handler) end

--- A coroutine's lifetime and cancellation handle. Its children are launched
--- through a CoroutineScope whose context contains this Job.
---@class luastd.async.Job
local Job = {}

--- Cancel this Job and its children.
function Job:cancel() end

--- Whether this Job is active.
---@return boolean
function Job:is_active() end

--- Whether this Job was cancelled.
---@return boolean
function Job:is_cancelled() end

--- Whether this Job and its children have finished.
---@return boolean
function Job:is_completed() end

--- Run `handler` when this Job ends without completing normally.
---@param handler fun()
function Job:on_cancel(handler) end

--- A handle to a launched coroutine that also produces values; collect them
--- with `async.await(d)` or `async.try_await(d)`.
---@class luastd.async.Deferred<T...>: luastd.async.Job

--- A job that produces the values `T...`, the body's return values; collect
--- them with `async.await(d)` or `async.try_await(d)`.
---@class luastd.async.Deferred<T...>: luastd.async.Job

--- Launch `body` as a child of the current scope, or of the Job in `context`.
---
--- In a non-supervisor scope, a failure cancels the scope and its other
--- children. In a supervisor scope, an unhandled failure is reported on stderr.
---@overload fun(context: luastd.async.CoroutineContext, body: async fun(scope: luastd.async.Scope)): luastd.async.Job
---@param context_or_body luastd.async.CoroutineContext | async fun(scope: luastd.async.Scope)
---@param body?           async fun(scope: luastd.async.Scope)
---@return luastd.async.Job
function async.launch(context_or_body, body) end

--- Wait for each job in argument order without raising child failures.
--- Like `join`, cancellation of the caller is raised at the current wait.
---@async
---@param ... luastd.async.Job
function async.join_all(...) end

--- Start `body` as a child of the current scope; collect it with `async.await`.
---@generic T...
---@param body fun(scope: luastd.async.Scope): T...
---@return luastd.async.Deferred<T...>
function async.async(body) end

--- Wait until `job` and its children have finished, however they ended; the
--- canonical (and only) way to wait for a job. It never raises the job's
--- failure, so there is no `try_join`.
---
--- Like every suspension point, it raises the cancellation error when the
--- caller is cancelled, even if `job` has already finished.
---@async
---@param job luastd.async.Job
function async.join(job) end

--- Wait for `deferred` and return every value its body returned; the
--- canonical way to collect a value. Re-raises the job's failure, and raises
--- `JobCancelled` when the job was cancelled. To handle the failure as a value
--- use `async.try_await`.
---
--- A failing child of a (non-supervisor) scope also cancels that scope, so
--- awaiting it from the same scope raises the cancellation instead, which no
--- `pcall` or `try_*` catches (ADR 0005). Run the work in its own scope to
--- recover from it:
---
--- ```lua
--- local ok, orders = async.try_scope(function () return api.orders(id) end)
--- if not ok then log(orders.kind) end -- `orders` is the error here
--- ```
---@async
---@generic T...
---@param deferred luastd.async.Deferred<T...>
---@return T...
function async.await(deferred) end

--- `try_*` form of `async.await`: `true` and the body's values, or `false`
--- and the job's failure (`JobCancelled` when the job was cancelled) instead
--- of raising it.
---
--- The caller's own cancellation is not caught (ADR 0005): when the caller is
--- cancelled, including by the awaited child failing in the caller's scope,
--- the cancellation propagates and nothing is returned. Use `async.try_scope`
--- to contain such a child.
---@async
---@generic T...
---@param deferred luastd.async.Deferred<T...>
---@return_overload true, T...
---@return_overload false, luastd.Error
function async.try_await(deferred) end

--- Await each deferred in argument order and return the first value of each,
--- so there is one result per argument even when a body returns several.
--- Raises the first failure reached in that order.
---@async
---@param ... luastd.async.Deferred
---@return any ...
function async.await_all(...) end

--- Run `body` in a new scope and wait for its children. A failing child
--- cancels the scope; its error is raised here. Returns the body's values.
--- The canonical form; `async.try_scope` returns the failure instead.
---@async
---@generic T...
---@param body fun(scope: luastd.async.Scope): T...
---@return T...
function async.scope(body) end

--- `try_*` form of `async.scope`: `true` and the body's values, or `false`
--- and the failure of the body or of a child, instead of raising it. The
--- scope contains the failure: a failing child cancels only this scope and
--- its other children, never the caller's scope, so the caller continues.
---
--- ```lua
--- local ok, orders = async.try_scope(function () return api.orders(id) end)
--- ```
---
--- Cancellation is not caught (ADR 0005): when the caller is cancelled, or
--- the body cancels its own scope, the cancellation propagates.
---@async
---@generic T...
---@param body fun(scope: luastd.async.Scope): T...
---@return_overload true, T...
---@return_overload false, luastd.Error
function async.try_scope(body) end

--- Like `scope`, but children fail independently of each other and the scope.
---@async
---@generic T...
---@param body fun(scope: luastd.async.Scope): T...
---@return T...
function async.supervisor_scope(body) end

--- Run `body` in a scope that is cancelled after `ms` milliseconds; raises
--- `Timeout` (a catchable `luastd.Error`) when it is, with the message
--- `"Timed out waiting for <ms> ms"`. As in kotlinx.coroutines, `ms <= 0`
--- raises `Timeout` (`"Timed out immediately"`) without running `body`.
--- When the effective context has a `CoroutineName`, the timeout message
--- starts with `Coroutine "<name>"`.
---@async
---@generic T...
---@param ms   number
---@param body fun(scope: luastd.async.Scope): T...
---@return T...
function async.with_timeout(ms, body) end

--- A name carried in a coroutine context. Child jobs inherit the effective
--- name; a nested `with_context` can temporarily replace it.
---@class luastd.async.CoroutineName
---@field name string
local CoroutineName = {}

--- Create a coroutine-name context element.
---@param name string
---@return luastd.async.CoroutineName
function async.coroutine_name(name) end

--- An immutable set of coroutine-context elements, including an optional Job
--- and CoroutineName.
---@class luastd.async.CoroutineContext
local CoroutineContext = {}

--- Get the Job associated with this context, if it contains one.
---@return luastd.async.Job?
function CoroutineContext:job() end

--- Get the effective coroutine name, if set.
---@return string?
function CoroutineContext:coroutine_name() end

--- Combine Job, CoroutineName, and other CoroutineContext values. When an
--- element key is repeated, the last value wins, as in Kotlin's CoroutineContext.
---@param ... luastd.async.Job | luastd.async.CoroutineName | luastd.async.CoroutineContext
---@return luastd.async.CoroutineContext
function async.context(...) end

--- Create a standalone supervisor Job. Its child failures do not cancel it or
--- one another; the runtime cancels it when the current `Runtime::run` ends.
---@return luastd.async.Job
function async.supervisor_job() end

--- Run `body` in a lexically scoped coroutine with the supplied elements
--- combined with the caller's context. Unspecified elements are inherited;
--- a supplied Job becomes the scope's parent. The caller's context is restored
--- on return, error, or cancellation.
---@async
---@generic T...
---@param context luastd.async.CoroutineContext
---@param body    fun(scope: luastd.async.Scope): T...
---@return T...
function async.with_context(context, body) end

--- The effective context of the currently running coroutine.
---@return luastd.async.CoroutineContext
function async.current_context() end

--- Suspend for `ms` milliseconds.
---@async
---@param ms number
function async.delay(ms) end

--- Let other coroutines run; a cancellation point. It guarantees that other
--- ready coroutines get a turn, not in which order: it is tokio's
--- `yield_now`, which also runs coroutines woken during the same round (such as
--- the waiters of a job that just finished) before the caller resumes.
---@async
function async.yield() end

--- Whether the current coroutine's scope has not been cancelled.
---@return boolean
function async.is_active() end

--- The current scope (the root scope outside any job or scope).
---@return luastd.async.Scope
function async.current() end

--- Whether `err` is the cancellation error.
---@param err any
---@return boolean
function async.is_cancellation(err) end

--- Run `body`, then `cleanup` however `body` ended, including cancellation.
--- `cleanup` cannot be cancelled. Errors from `body` win over `cleanup`'s.
---@async
---@generic T...
---@param body    fun(): T...
---@param cleanup fun()
---@return T...
function async.finally(body, cleanup) end

--- A channel between coroutines carrying values of type `T`; `send` and
--- `receive` suspend. Plain `luastd.async.Channel` carries anything; annotate
--- the element type where it helps:
---
--- ```lua
--- ---@type luastd.async.Channel<string>
--- local lines = async.channel(16)
--- ```
---
--- Element types are not checked at runtime.
---@class luastd.async.Channel<T = any>
local Channel = {}

--- A channel with room for `cap` values (default 0: each `send` waits for a
--- `receive`).
---@param cap? integer
---@return luastd.async.Channel
function async.channel(cap) end

--- Send a non-nil value, waiting for room. On a cancelled channel the sending
--- coroutine is cancelled quietly: its scope sees no error.
---@async
---@param value T
function Channel:send(value) end

--- Receive the next value, waiting for one. Values sent before `close` are
--- still delivered.
---@async
---@return T
function Channel:receive() end

--- Close the channel; waiting receivers see the end of the stream.
function Channel:close() end

--- Close the channel, drop buffered values, and cancel pending and future
--- senders, including the producer job of a `produce` channel. Call it when a
--- consumer stops early.
function Channel:cancel() end

--- Whether `close` or `cancel` has been called.
---@return boolean
function Channel:is_closed() end

--- Iterate values until the channel is closed and drained.
---
--- Leaving the loop early (`break`, `return`, an error) does **not** cancel
--- the producer: it waits on its next `send`, and its scope waits for it. Use
--- `each`, or call `cancel` after the loop.
---@async
---@return fun(): T?
function Channel:iter() end

--- Call `fn` with each value until the channel is closed and drained, or `fn`
--- returns `false`. However it ends, including an error or cancellation, the
--- channel is cancelled, so its producer stops.
---@async
---@param fn fun(value: T): boolean?
function Channel:each(fn) end

--- A channel that emits a value once `ms` milliseconds pass without a newer
--- one, and the last value when this channel closes. Runs a job in the
--- current scope until this channel closes.
---@param ms number
---@return luastd.async.Channel<T>
function Channel:debounce(ms) end

--- Run `body` as a producer job in the current scope and return its channel.
--- The channel is closed when `body` ends, and the producer is cancelled when
--- the consumer calls `cancel` (or `each` ends).
---@generic T
---@param body async fun(channel: luastd.async.Channel<T>, scope: luastd.async.Scope)
---@param cap? integer
---@return luastd.async.Channel<T>
function async.produce(body, cap) end

--- Wrap `fn` so that only the last call in a burst runs, `ms` milliseconds
--- after it, as a job in the scope that created the wrapper. A call that has
--- already started is not cancelled.
---@generic F: function
---@param ms number
---@param fn F
---@return fun(...): luastd.async.Job
function async.debounce(ms, fn) end

--- Wrap `fn` so that it runs at most once per `ms` milliseconds; calls in
--- between are dropped (leading edge).
---@generic F: function
---@param ms number
---@param fn F
---@return F
function async.throttle(ms, fn) end

return async
