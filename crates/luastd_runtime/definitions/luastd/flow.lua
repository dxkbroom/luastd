---@meta luastd.flow

--- Cold flows: lazily-computed asynchronous streams. Nothing runs until a
--- terminal operator collects the flow.
---@class luastd.flow.Flow<T = any>
local Flow = {}

---@class luastd.flow
local flow = {}

--- Build a flow whose `body` receives an `emit` function and may suspend.
---@param body async fun(emit: fun(value: any))
---@return luastd.flow.Flow
function flow.new(body) end

--- Build a flow from a table of values.
---@param values any[]
---@return luastd.flow.Flow
function flow.from(values) end

--- Build a flow that emits a single value.
---@param value any
---@return luastd.flow.Flow
function flow.of_one(value) end

--- Collect every value, calling `fn` for each.
---@async
---@param fn fun(value: any)
function Flow:collect(fn) end

--- Collect all values into a table.
---@async
---@return any[]
function Flow:to_list() end

--- The first value, then cancel upstream.
---@async
---@return any
function Flow:first() end

--- The single value (errors if not exactly one).
---@async
---@return any
function Flow:single() end

--- The number of values.
---@async
---@return integer
function Flow:count() end

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

--- Take the first `n` values, then cancel upstream.
---@param n integer
---@return luastd.flow.Flow
function Flow:take(n) end

--- Drop the first `n` values.
---@param n integer
---@return luastd.flow.Flow
function Flow:drop(n) end

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

--- Buffer upstream with a channel of capacity `cap`.
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
---@param op fun(acc: any, value: any): any
---@return luastd.flow.Flow
function Flow:scan(initial, op) end

--- Retry the flow up to `n` times on error.
---@param n? integer
---@return luastd.flow.Flow
function Flow:retry(n) end

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
---@param other luastd.flow.Flow
---@param transform? fun(a: any, b: any): any
---@return luastd.flow.Flow
function Flow:zip(other, transform) end

--- Combine latest values from two flows.
---@param other luastd.flow.Flow
---@param transform? fun(a: any, b: any): any
---@return luastd.flow.Flow
function Flow:combine(other, transform) end

return flow
