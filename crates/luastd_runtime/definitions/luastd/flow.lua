---@meta luastd.flow

--- Cold flows: lazily-computed asynchronous streams. Nothing runs until a
--- terminal operator collects the flow.
---@class luastd.flow.Flow<T = any>
local Flow = {}

---@class luastd.flow
local flow = {}

--- Build a flow whose `body` receives an `emit` function and may suspend.
---@generic T
---@param body async fun(emit: fun(value: T))
---@return luastd.flow.Flow<T>
function flow.new(body) end

--- Build a flow from a table of values.
---@generic T
---@param values table<integer, T>
---@return luastd.flow.Flow<T>
function flow.from(values) end

--- Build an empty flow.
---@generic T
---@return luastd.flow.Flow<T>
function flow.empty() end

--- Build a flow that emits a single value.
---@generic T
---@param value T
---@return luastd.flow.Flow<T>
function flow.of_one(value) end

--- Collect every value, calling `fn` for each.
---@async
---@param fn fun(value: T)
function Flow:collect(fn) end

--- Collect every value with its zero-based index.
---@async
---@param fn fun(index: integer, value: T)
function Flow:collect_indexed(fn) end

--- Pair each value with its zero-based index.
---@return luastd.flow.Flow<{ index: integer, value: T }>
function Flow:with_index() end

--- Collect all values into a table.
---@async
---@return table<integer, T>
function Flow:to_list() end

--- The first value (or first matching `predicate`), then cancel upstream.
---@async
---@param predicate? fun(value: T): boolean
---@return T
function Flow:first(predicate) end

--- The single value (or single matching `predicate`).
---@async
---@param predicate? fun(value: T): boolean
---@return T
function Flow:single(predicate) end

--- The last value.
---@async
---@return T
function Flow:last() end

--- The number of values.
---@async
---@return integer
function Flow:count() end

--- True if all values match.
---@async
---@param predicate fun(value: T): boolean
---@return boolean
function Flow:all(predicate) end

--- True if any value matches.
---@async
---@param predicate fun(value: T): boolean
---@return boolean
function Flow:any(predicate) end

--- True if no value matches.
---@async
---@param predicate fun(value: T): boolean
---@return boolean
function Flow:none(predicate) end

--- Fold with an initial accumulator.
---@async
---@generic U
---@param initial U
---@param op      fun(acc: U, value: T): U
---@return U
function Flow:fold(initial, op) end

--- Reduce (no initial; errors on empty).
---@async
---@param op fun(acc: T, value: T): T
---@return T
function Flow:reduce(op) end

--- Build a map from transformed key/value pairs; later duplicate keys replace earlier values.
---@async
---@generic K, V
---@param transform fun(value: T): K, V
---@return table<K, V>
function Flow:associate(transform) end

--- Add transformed key/value pairs to `target` and return that same table.
---@async
---@generic K, V, M: table<K, V>
---@param target    M
---@param transform fun(value: T): K, V
---@return M
function Flow:associate_to(target, transform) end

--- Build a map keyed by each value's selected key; later duplicate keys replace earlier values.
---@async
---@generic K, V
---@overload fun(self: luastd.flow.Flow<T>, key_selector: fun(value: T): K): table<K, T>
---@param key_selector     fun(value: T): K
---@param value_transform? fun(value: T): V
---@return table<K, V>
function Flow:associate_by(key_selector, value_transform) end

--- Add values keyed by a selector to `target` and return that same table.
---@async
---@generic K, V, M: table<K, V>
---@overload fun(self: luastd.flow.Flow<T>, target: M, key_selector: fun(value: T): K): M
---@param target           M
---@param key_selector     fun(value: T): K
---@param value_transform? fun(value: T): V
---@return M
function Flow:associate_by_to(target, key_selector, value_transform) end

--- Build a map using each value as its key.
---@async
---@generic V
---@param value_transform fun(value: T): V
---@return table<T, V>
function Flow:associate_with(value_transform) end

--- Add value-keyed transformed values to `target` and return that same table.
---@async
---@generic M: table<T, V>, V
---@param target          M
---@param value_transform fun(value: T): V
---@return M
function Flow:associate_with_to(target, value_transform) end

--- Group values by a selected key, preserving source order inside each group.
---@async
---@generic K, V
---@overload fun(self: luastd.flow.Flow<T>, key_selector: fun(value: T): K): table<K, table<integer, T>>
---@param key_selector     fun(value: T): K
---@param value_transform? fun(value: T): V
---@return table<K, table<integer, V>>
function Flow:group_by(key_selector, value_transform) end

--- Add values to groups in `target` and return that same table.
---@async
---@generic K, V, M: table<K, table<integer, V>>
---@overload fun(self: luastd.flow.Flow<T>, target: M, key_selector: fun(value: T): K): M
---@param target           M
---@param key_selector     fun(value: T): K
---@param value_transform? fun(value: T): V
---@return M
function Flow:group_by_to(target, key_selector, value_transform) end

--- Transform each value.
---@generic U
---@param fn fun(value: T): U
---@return luastd.flow.Flow<U>
function Flow:map(fn) end

--- Transform each value, dropping nil results.
---@generic U
---@param fn fun(value: T): U?
---@return luastd.flow.Flow<U>
function Flow:map_not_null(fn) end

--- Keep values matching the predicate.
---@param predicate fun(value: T): boolean
---@return luastd.flow.Flow<T>
function Flow:filter(predicate) end

--- Emit each upstream value and run `fn` with it (side effect).
---@param fn fun(value: T)
---@return luastd.flow.Flow<T>
function Flow:on_each(fn) end

--- Run `fn` when the flow completes (err is nil on success).
---@param fn fun(err: any?)
---@return luastd.flow.Flow<T>
function Flow:on_completion(fn) end

--- Run `fn` before collection starts.
---@param fn fun(emit: fun(value: T))
---@return luastd.flow.Flow<T>
function Flow:on_start(fn) end

--- Run `fn` when the flow completes without emitting any value.
---@param fn fun()
---@return luastd.flow.Flow<T>
function Flow:on_empty(fn) end

--- Take the first `n` values, then cancel upstream.
---@param n integer
---@return luastd.flow.Flow<T>
function Flow:take(n) end

--- Share this flow eagerly in `scope` and expose the latest value as a read-only state flow.
--- With `initial`, return immediately using that value until upstream emits.
--- Without it, suspend until upstream emits its first value; empty upstream fails.
---@async
---@overload fun<T>(self: luastd.flow.Flow<T>, scope: luastd.async.Scope): luastd.flow.StateFlow<T>
---@generic T
---@param scope   luastd.async.Scope
---@param initial T
---@return luastd.flow.StateFlow<T>
function Flow:state_in(scope, initial) end

--- Drop the first `n` values.
---@param n integer
---@return luastd.flow.Flow<T>
function Flow:drop(n) end

--- Drop values while the predicate holds.
---@param predicate fun(value: T): boolean
---@return luastd.flow.Flow<T>
function Flow:drop_while(predicate) end

--- Take values while the predicate holds.
---@param predicate fun(value: T): boolean
---@return luastd.flow.Flow<T>
function Flow:take_while(predicate) end

--- Transform with full control over emission.
---@generic U
---@param fn fun(emit: fun(value: U), value: T)
---@return luastd.flow.Flow<U>
function Flow:transform(fn) end

--- Emit a value only after `ms` ms without a newer one.
---@param ms number
---@return luastd.flow.Flow<T>
function Flow:debounce(ms) end

--- Raise a Timeout error if upstream is inactive for `ms` milliseconds.
--- The timeout restarts after each upstream value; `ms <= 0` fails before
--- upstream starts. An upstream error is forwarded unchanged.
---@param ms number
---@return luastd.flow.Flow<T>
function Flow:timeout(ms) end

--- Emit only values distinct from the previous.
---@generic K
---@param key?       fun(value: T): K
---@param are_equal? fun(a: K, b: K): boolean
---@return luastd.flow.Flow<T>
function Flow:distinct_until_changed(key, are_equal) end

--- Run upstream on `context`.
---@param context luastd.async.CoroutineContext
---@return luastd.flow.Flow<T>
function Flow:flow_on(context) end

--- Check the current coroutine's cancellation state before each emission.
--- Already-cancellable builder flows are returned unchanged.
---@return luastd.flow.Flow<T>
function Flow:cancellable() end

--- Buffer upstream with a channel of capacity `cap` (default 64).
---@param cap? integer
---@return luastd.flow.Flow<T>
function Flow:buffer(cap) end

--- Catch an error from upstream and optionally emit recovery values.
---@param handler fun(emit: fun(value: T), err: any)
---@return luastd.flow.Flow<T>
function Flow:catch(handler) end

--- Run `inner` for each value and concatenate its emissions.
---@generic U
---@param fn fun(value: T): luastd.flow.Flow<U>
---@return luastd.flow.Flow<U>
function Flow:flat_map_concat(fn) end

--- Run `inner` for each value and merge emissions.
---@generic U
---@param fn fun(value: T): luastd.flow.Flow<U>
---@return luastd.flow.Flow<U>
function Flow:flat_map_merge(fn) end

--- Run `inner` for each value, cancelling the previous inner.
---@generic U
---@param fn fun(value: T): luastd.flow.Flow<U>
---@return luastd.flow.Flow<U>
function Flow:flat_map_latest(fn) end

--- Transform with cancellation of the previous transform.
---@generic U
---@param fn fun(emit: fun(value: U), value: T)
---@return luastd.flow.Flow<U>
function Flow:transform_latest(fn) end

--- Transform while `fn` returns true.
---@generic U
---@param fn fun(emit: fun(value: U), value: T): boolean?
---@return luastd.flow.Flow<U>
function Flow:transform_while(fn) end

--- Emit running accumulator, starting with `initial`.
---@generic U
---@param initial U
---@param op      fun(acc: U, value: T): U
---@return luastd.flow.Flow<U>
function Flow:scan(initial, op) end

--- Retry the flow up to `n` times on error.
---@param n?         integer
---@param predicate? fun(cause: any): boolean Retry only when this returns true.
---@return luastd.flow.Flow<T>
function Flow:retry(n, predicate) end

--- Retry after upstream errors while `predicate(cause, attempt)` returns true.
--- The first attempt number is 0. Errors raised by downstream callbacks are never retried.
---@param predicate fun(cause: any, attempt: integer): boolean
---@return luastd.flow.Flow<T>
function Flow:retry_when(predicate) end

--- Group values into chunks of `size`.
---@param size integer
---@return luastd.flow.Flow<table<integer, T>>
function Flow:chunked(size) end

--- Keep only the latest value when the collector is slow (no-op in sync model).
---@return luastd.flow.Flow<T>
function Flow:conflate() end

--- Collect with cancellation of the previous collector (sync: like collect).
---@param fn fun(value: T)
function Flow:collect_latest(fn) end

--- Pair values from two flows by index.
---@generic U, R
---@overload fun(self: luastd.flow.Flow<T>, other: luastd.flow.Flow<U>): luastd.flow.Flow<{ T, U }>
---@param other      luastd.flow.Flow<U>
---@param transform? fun(a: T, b: U): R
---@return luastd.flow.Flow<R>
function Flow:zip(other, transform) end

--- Combine latest values from two flows.
---@generic U, R
---@overload fun(self: luastd.flow.Flow<T>, other: luastd.flow.Flow<U>): luastd.flow.Flow<{ T, U }>
---@param other      luastd.flow.Flow<U>
---@param transform? fun(a: T, b: U): R
---@return luastd.flow.Flow<R>
function Flow:combine(other, transform) end

--- Merge several flows into one.
---@generic T
---@param flows luastd.flow.Flow<T>[]
---@return luastd.flow.Flow<T>
function flow.merge(flows) end

--- Merge another flow into this one.
---@param other luastd.flow.Flow<T>
---@return luastd.flow.Flow<T>
function Flow:merge(other) end

--- A hot flow that replays the last `replay` values to new subscribers.
---@class luastd.flow.SharedFlow<T = any>: luastd.flow.Flow<T>
local SharedFlow = {}

--- Snapshot of the current replay buffer. `n` preserves its size when values are `nil`.
---@type table<integer, T>
SharedFlow.replay_cache = {}

--- Number of active collectors.
---@type integer
SharedFlow.subscription_count = 0

--- Emit a value to all subscribers.
---@param value T
function SharedFlow:emit(value) end

--- Try to emit without suspending.
---@param value T
---@return boolean
function SharedFlow:try_emit(value) end

--- Clear values available to future subscribers without changing active collectors.
function SharedFlow:reset_replay_cache() end

--- Run `action` after a collector subscribes and before replayed values are delivered.
---@param action fun(emit: fun(value: T))
---@return luastd.flow.SharedFlow<T>
function SharedFlow:on_subscription(action) end

--- The underlying flow (for chaining).
---@return luastd.flow.Flow<T>
function SharedFlow:as_shared_flow() end

--- Create a mutable shared flow.
---@generic T
---@param replay?       integer
---@param extra_buffer? integer
---@param on_overflow?  "SUSPEND" | "DROP_OLDEST" | "DROP_LATEST"
---@return luastd.flow.SharedFlow<T>
function flow.mutable_shared_flow(replay, extra_buffer, on_overflow) end

--- A read-only state flow holding a single state value.
---@class luastd.flow.StateFlow<T = any>: luastd.flow.SharedFlow<T>
local StateFlow = {}

--- The current state value.
---@type T
StateFlow.value = nil

--- A mutable state flow with one current state value.
---@class luastd.flow.MutableStateFlow<T = any>: luastd.flow.StateFlow<T>
local MutableStateFlow = {}

---@type T
MutableStateFlow.value = nil

--- Update the state with `fn(old)`.
---@param fn fun(old: T): T
function MutableStateFlow:update(fn) end

--- Set the state if it equals `old`.
---@param old T
---@param new T
---@return boolean
function MutableStateFlow:compare_and_set(old, new) end

--- Create a mutable state flow seeded with `initial`.
---@generic T
---@param initial T
---@return luastd.flow.MutableStateFlow<T>
function flow.mutable_state_flow(initial) end

return flow
