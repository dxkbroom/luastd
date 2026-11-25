# Cold Flow API sketch (draft)

Status: draft, 2026-11-22. Module: `luastd.flow` (pure, built on channels/coroutines).
Convention: snake_case. Method chaining returns a new `Flow`, so LSP sees a stable
type through a chain. Multi-argument / optional-argument functions take a single
table (named fields) instead of `...`, so autocomplete and type-checking stay
precise. Single-primary-argument operators (`map`, `filter`, ...) also accept the
function positionally as a shortcut.

```lua
local flow = require("luastd.flow")
local async = require("luastd.async")

--- A cold flow: nothing runs until a terminal operator collects it.
---@class luastd.flow.Flow<T>

-- ---------- builders ----------
--- Build a flow from `body`, which receives an `emit` function.
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

-- ---------- terminals ----------
---@async
---@param fn fun(value: any)
function Flow:collect(fn) end

---@async
---@return any[]
function Flow:to_list() end

---@async
---@return any
function Flow:first() end

---@async
---@return any
function Flow:single() end

---@async
---@return integer
function Flow:count() end

---@async
---@param initial any
---@param op fun(acc: any, value: any): any
---@return any
function Flow:fold(initial, op) end

---@async
---@param op fun(acc: any, value: any): any
---@return any
function Flow:reduce(op) end

-- ---------- operators (return a new Flow) ----------

--- Transform each value.
---@param opts { fn: fun(value: any): any } | fun(value: any): any
---@return luastd.flow.Flow
function Flow:map(opts) end

--- Keep values matching the predicate.
---@param opts { predicate: fun(value: any): boolean } | fun(value: any): boolean
---@return luastd.flow.Flow
function Flow:filter(opts) end

--- Emit each upstream value, then run `fn` with it (side effect).
---@param opts { fn: fun(value: any) } | fun(value: any)
---@return luastd.flow.Flow
function Flow:on_each(opts) end

--- Run `fn` when the flow completes (err is nil on success).
---@param opts { fn: fun(err: luastd.Error?) }
---@return luastd.flow.Flow
function Flow:on_completion(opts) end

--- Run `fn` before collection starts.
---@param opts { fn: fun() }
---@return luastd.flow.Flow
function Flow:on_start(opts) end

--- Take the first `n` values, then cancel upstream.
---@param n integer
---@return luastd.flow.Flow
function Flow:take(n) end

--- Drop the first `n` values.
---@param n integer
---@return luastd.flow.Flow
function Flow:drop(n) end

--- Transform with full control over emission.
---@param opts { fn: async fun(emit: fun(value: any), value: any) }
---@return luastd.flow.Flow
function Flow:transform(opts) end

--- Emit a value only when `ms` ms pass without a newer one.
---@param ms number
---@return luastd.flow.Flow
function Flow:debounce(ms) end

--- Emit only values distinct from the previous (by `key`, default identity).
---@param opts? { key: fun(value: any): any }
---@return luastd.flow.Flow
function Flow:distinct_until_changed(opts) end

--- Run upstream on `context` (context switching).
---@param context luastd.async.CoroutineContext
---@return luastd.flow.Flow
function Flow:flow_on(context) end

--- Buffer upstream with a channel of capacity `cap`.
---@param cap? integer
---@return luastd.flow.Flow
function Flow:buffer(cap) end

--- Catch an error from upstream and optionally emit recovery values.
---@param opts { handler: fun(emit: fun(value: any), err: luastd.Error) }
---@return luastd.flow.Flow
function Flow:catch(opts) end

-- ---------- example chain ----------
local result = flow.from({ 1, 2, 3, 4 })
    :filter({ predicate = function (x) return x % 2 == 0 end })
    :map({ fn = function (x) return x * 10 end })
    :take(2)
    :to_list()
-- result == { 20, 40 }
```

Implemented now: `flatMapConcat`, `flatMapMerge`, `flatMapLatest`,
`transformLatest`, `transformWhile`, `scan`, `retry`, `chunked`, `conflate`,
`collectLatest`, `zip`, `combine`.

Still deferred: `SharedFlow`, `StateFlow`, `stateIn`, `shareIn`
(separate track — replay buffer + subscription model).

## Implementation notes

- A `Flow` is a function `collect(emit)`; operators return a new Flow wrapping
  the upstream. Collection runs the whole chain in one coroutine, emitting into
  a channel so backpressure and cancellation propagate.
- `flowOn` switches the upstream's context using `async.with_context`.
- Pure Lua over channels; no Rust changes needed for v1.
