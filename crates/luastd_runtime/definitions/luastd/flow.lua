---@meta luastd.flow

--- Cold flows: lazily-computed asynchronous streams. Nothing runs until a
--- terminal operator collects the flow.
---@class luastd.flow.Flow<T = any>
local Flow = {}

---@class luastd.flow
local flow = {}

--- Build a flow whose `body` receives an `emit` function and may suspend.
---@return luastd.flow.Flow
---@param body async fun(emit: fun(value: any))
function flow.new(body) end

--- Build a flow from a table of values.
---@param values table<integer, any>
---@return luastd.flow.Flow
function flow.from(values) end

--- Build an empty flow.
---@return luastd.flow.Flow
function flow.empty() end

--- Build a flow that emits a single value.
---@param value any
---@return luastd.flow.Flow
function flow.of_one(value) end

--- Collect every value, calling `fn` for each.
---@async
---@param fn fun(value: any)
function Flow:collect(fn) end

--- Collect every value with its zero-based index.
---@async
---@param fn fun(index: integer, value: any)
function Flow:collect_indexed(fn) end

--- Pair each value with its zero-based index.
---@return luastd.flow.Flow
function Flow:with_index() end

--- Collect all values into a table.
---@async
---@return table<integer, any>
function Flow:to_list() end

--- The first value (or first matching `predicate`), then cancel upstream.
---@async
---@param predicate? fun(value: any): boolean
---@return any
function Flow:first(predicate) end

--- The single value (or single matching `predicate`).
---@async
---@param predicate? fun(value: any): boolean
---@return any
function Flow:single(predicate) end

--- The last value.
---@async
---@return any
function Flow:last() end

--- The number of values.
---@async
---@return integer
function Flow:count() end

--- True if all values match.
---@async
---@param predicate fun(value: any): boolean
---@return boolean
function Flow:all(predicate) end

--- True if any value matches.
---@async
---@param predicate fun(value: any): boolean
---@return boolean
function Flow:any(predicate) end

--- True if no value matches.
---@async
---@param predicate fun(value: any): boolean
---@return boolean
function Flow:none(predicate) end

--- Fold with an initial accumulator.
---@async
---@param initial any
---@param op      fun(acc: any, value: any): any
---@return any
function Flow:fold(initial, op) end

--- Reduce (no initial; errors on empty).
---@async
---@param op fun(acc: any, value: any): any
---@return any
function Flow:reduce(op) end

--- Transform each value.
---@param fn fun(value: any): any
---@return luastd.flow.Flow
function Flow:map(fn) end

--- Transform each value, dropping nil results.
---@param fn fun(value: any): any
---@return luastd.flow.Flow
function Flow:map_not_null(fn) end

--- Keep values matching the predicate.
---@param predicate fun(value: any): boolean
---@return luastd.flow.Flow
function Flow:filter(predicate) end

--- Emit each upstream value and run `fn` with it (side effect).
---@param fn fun(value: any)
---@return luastd.flow.Flow
function Flow:on_each(fn) end

--- Run `fn` when the flow completes (err is nil on success).
---@param fn fun(err: luastd.Error?)
function Flow:on_completion(fn) end

--- Run `fn` before collection starts.
---@param fn fun()
---@return luastd.flow.Flow
function Flow:on_start(fn) end

--- Run `fn` when the flow completes without emitting any value.
---@param fn fun()
---@return luastd.flow.Flow
function Flow:on_empty(fn) end

--- Take the first `n` values, then cancel upstream.
---@param n integer
---@return luastd.flow.Flow
function Flow:take(n) end

--- Drop the first `n` values.
---@param n integer
---@return luastd.flow.Flow
function Flow:drop(n) end

--- Drop values while the predicate holds.
---@param predicate fun(value: any): boolean
---@return luastd.flow.Flow
function Flow:drop_while(predicate) end

--- Take values while the predicate holds.
---@param predicate fun(value: any): boolean
---@return luastd.flow.Flow
function Flow:take_while(predicate) end

--- Transform with full control over emission.
---@param fn fun(emit: fun(value: any), value: any)
---@return luastd.flow.Flow
function Flow:transform(fn) end

--- Emit a value only after `ms` ms without a newer one.
---@param ms number
---@return luastd.flow.Flow
function Flow:debounce(ms) end

--- Emit only values distinct from the previous.
---@param key?       fun(value: any): any
---@param are_equal? fun(a: any, b: any): boolean
---@return luastd.flow.Flow
function Flow:distinct_until_changed(key, are_equal) end

--- Run upstream on `context`.
---@param context luastd.async.CoroutineContext
---@return luastd.flow.Flow
function Flow:flow_on(context) end

--- Check the current coroutine's cancellation state before each emission.
--- Already-cancellable builder flows are returned unchanged.
---@return luastd.flow.Flow
function Flow:cancellable() end

--- Buffer upstream with a channel of capacity `cap` (default 64).
---@param cap? integer
---@return luastd.flow.Flow
function Flow:buffer(cap) end

--- Catch an error from upstream and optionally emit recovery values.
---@param handler fun(emit: fun(value: any), err: luastd.Error)
---@return luastd.flow.Flow
function Flow:catch(handler) end

--- Run `inner` for each value and concatenate its emissions.
---@param fn fun(value: any): luastd.flow.Flow
---@return luastd.flow.Flow
function Flow:flat_map_concat(fn) end

--- Run `inner` for each value and merge emissions.
---@param fn fun(value: any): luastd.flow.Flow
---@return luastd.flow.Flow
function Flow:flat_map_merge(fn) end

--- Run `inner` for each value, cancelling the previous inner.
---@param fn fun(value: any): luastd.flow.Flow
---@return luastd.flow.Flow
function Flow:flat_map_latest(fn) end

--- Transform with cancellation of the previous transform.
---@param fn fun(emit: fun(value: any), value: any)
---@return luastd.flow.Flow
function Flow:transform_latest(fn) end

--- Transform while `fn` returns true.
---@param fn fun(emit: fun(value: any), value: any): boolean?
---@return luastd.flow.Flow
function Flow:transform_while(fn) end

--- Emit running accumulator, starting with `initial`.
---@param initial any
---@param op      fun(acc: any, value: any): any
---@return luastd.flow.Flow
function Flow:scan(initial, op) end

--- Retry the flow up to `n` times on error.
---@param n?         integer
---@param predicate? fun(cause: any): boolean Retry only when this returns true.
---@return luastd.flow.Flow
function Flow:retry(n, predicate) end

--- Retry after upstream errors while `predicate(cause, attempt)` returns true.
--- The first attempt number is 0. Errors raised by downstream callbacks are never retried.
---@param predicate fun(cause: any, attempt: integer): boolean
---@return luastd.flow.Flow
function Flow:retry_when(predicate) end

--- Group values into chunks of `size`.
---@param size integer
---@return luastd.flow.Flow
function Flow:chunked(size) end

--- Keep only the latest value when the collector is slow (no-op in sync model).
---@return luastd.flow.Flow
function Flow:conflate() end

--- Collect with cancellation of the previous collector (sync: like collect).
---@param fn fun(value: any)
function Flow:collect_latest(fn) end

--- Pair values from two flows by index.
---@param other      luastd.flow.Flow
---@param transform? fun(a: any, b: any): any
---@return luastd.flow.Flow
function Flow:zip(other, transform) end

--- Combine latest values from two flows.
---@param other      luastd.flow.Flow
---@param transform? fun(a: any, b: any): any
---@return luastd.flow.Flow
function Flow:combine(other, transform) end

--- Merge several flows into one.
---@param flows luastd.flow.Flow[]
---@return luastd.flow.Flow
function flow.merge(flows) end

--- Merge another flow into this one.
---@param other luastd.flow.Flow
---@return luastd.flow.Flow
function Flow:merge(other) end

--- A hot flow that replays the last `replay` values to new subscribers.
---@class luastd.flow.SharedFlow<T = any>: luastd.flow.Flow
local SharedFlow = {}

--- Emit a value to all subscribers.
---@param value any
function SharedFlow:emit(value) end

--- Try to emit without suspending.
---@param value any
---@return boolean
function SharedFlow:try_emit(value) end

--- The underlying flow (for chaining).
---@return luastd.flow.Flow
function SharedFlow:as_shared_flow() end

--- Create a mutable shared flow.
---@param replay?       integer
---@param extra_buffer? integer
---@param on_overflow?  "SUSPEND" | "DROP_OLDEST" | "DROP_LATEST"
---@return luastd.flow.SharedFlow
function flow.mutable_shared_flow(replay, extra_buffer, on_overflow) end

--- A shared flow holding a single state value.
---@class luastd.flow.StateFlow<T = any>: luastd.flow.SharedFlow
local StateFlow = {}

--- The current state value.
---@type any
StateFlow.value = nil

--- Update the state with `fn(old)`.
---@param fn fun(old: any): any
function StateFlow:update(fn) end

--- Set the state if it equals `old`.
---@param old any
---@param new any
---@return boolean
function StateFlow:compare_and_set(old, new) end

--- Create a mutable state flow seeded with `initial`.
---@param initial any
---@return luastd.flow.StateFlow
function flow.mutable_state_flow(initial) end

return flow
