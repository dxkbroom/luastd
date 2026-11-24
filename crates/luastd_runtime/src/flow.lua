-- luastd.flow: cold flows over channels and coroutines.
-- A Flow is a function `_run(emit)`; operators return a new Flow wrapping upstream.

local async = require("luastd.async")

local Flow = {}
Flow.__index = Flow

local BREAK = {}

local function new_flow(run)
    return setmetatable({ _run = run }, Flow)
end

local flow = {}

function flow.new(body)
    return new_flow(function (emit)
        body(emit)
    end)
end

function flow.from(values)
    return new_flow(function (emit)
        for _, v in ipairs(values) do
            emit(v)
        end
    end)
end

function flow.empty()
    return new_flow(function (emit) end)
end

function flow.of_one(value)
    return new_flow(function (emit)
        emit(value)
    end)
end

function Flow:collect(fn)
    self._run(fn)
end

function Flow:collect_indexed(fn)
    local i = 0
    self._run(function (v)
        fn(i, v)
        i = i + 1
    end)
end

function Flow:with_index()
    local up = self
    return new_flow(function (emit)
        local i = 0
        up._run(function (v)
            emit({ index = i, value = v })
            i = i + 1
        end)
    end)
end

function Flow:to_list()
    local acc = {}
    self._run(function (v) table.insert(acc, v) end)
    return acc
end

function Flow:first(pred)
    local result = nil
    local found = false
    local ok, err = pcall(function ()
        self._run(function (v)
            if found then return end
            if pred == nil or pred(v) then
                result = v
                found = true
                error(BREAK)
            end
        end)
    end)
    if not ok and not rawequal(err, BREAK) then
        error(err, 0)
    end
    if not found then
        error("NoSuchElementException")
    end
    return result
end

function Flow:single(pred)
    local acc = {}
    self._run(function (v)
        if pred == nil or pred(v) then table.insert(acc, v) end
    end)
    if #acc ~= 1 then
        error("expected a single value")
    end
    return acc[1]
end

function Flow:last()
    local result = nil
    local found = false
    self._run(function (v) result = v; found = true end)
    if not found then error("NoSuchElementException") end
    return result
end

function Flow:single()
    local acc = {}
    self._run(function (v) table.insert(acc, v) end)
    if #acc ~= 1 then
        error("expected a single value")
    end
    return acc[1]
end

function Flow:count()
    local n = 0
    self._run(function () n = n + 1 end)
    return n
end

function Flow:all(pred)
    local result = true
    self._run(function (v)
        if not pred(v) then result = false end
    end)
    return result
end

function Flow:any(pred)
    local result = false
    self._run(function (v)
        if pred(v) then result = true end
    end)
    return result
end

function Flow:none(pred)
    local result = true
    self._run(function (v)
        if pred(v) then result = false end
    end)
    return result
end

function Flow:fold(initial, op)
    local acc = initial
    self._run(function (v) acc = op(acc, v) end)
    return acc
end

function Flow:reduce(op)
    local acc = nil
    local first = true
    self._run(function (v)
        if first then acc = v; first = false
        else acc = op(acc, v) end
    end)
    if first then error("reduce on empty flow") end
    return acc
end

-- operators
function Flow:map(fn)
    local up = self
    return new_flow(function (emit)
        up._run(function (v) emit(fn(v)) end)
    end)
end

function Flow:map_not_null(fn)
    local up = self
    return new_flow(function (emit)
        up._run(function (v)
            local r = fn(v)
            if r ~= nil then emit(r) end
        end)
    end)
end

function Flow:filter(pred)
    local up = self
    return new_flow(function (emit)
        up._run(function (v)
            if pred(v) then emit(v) end
        end)
    end)
end

function Flow:on_each(fn)
    local up = self
    return new_flow(function (emit)
        up._run(function (v)
            fn(v)
            emit(v)
        end)
    end)
end

function Flow:on_completion(fn)
    local up = self
    return new_flow(function (emit)
        local ok, err = pcall(function () up._run(emit) end)
        fn(ok and nil or err)
        if not ok then error(err) end
    end)
end

function Flow:on_start(fn)
    local up = self
    return new_flow(function (emit)
        fn()
        up._run(emit)
    end)
end

function Flow:on_empty(fn)
    local up = self
    return new_flow(function (emit)
        local emitted = false
        up._run(function (v)
            emitted = true
            emit(v)
        end)
        if not emitted then fn() end
    end)
end

function Flow:take(n)
    local up = self
    return new_flow(function (emit)
        local count = 0
        local ok, err = pcall(function ()
            up._run(function (v)
                if count >= n then return end
                count = count + 1
                emit(v)
                if count >= n then error(BREAK) end
            end)
        end)
        if not ok and not rawequal(err, BREAK) then
            error(err, 0)
        end
    end)
end

function Flow:drop(n)
    local up = self
    return new_flow(function (emit)
        local count = 0
        up._run(function (v)
            if count < n then count = count + 1
            else emit(v) end
        end)
    end)
end

function Flow:drop_while(pred)
    local up = self
    return new_flow(function (emit)
        local dropping = true
        up._run(function (v)
            if dropping and pred(v) then
                -- drop
            else
                dropping = false
                emit(v)
            end
        end)
    end)
end

function Flow:take_while(pred)
    local up = self
    return new_flow(function (emit)
        local taking = true
        up._run(function (v)
            if not taking then return end
            if pred(v) then
                emit(v)
            else
                taking = false
            end
        end)
    end)
end

function Flow:transform(fn)
    local up = self
    return new_flow(function (emit)
        up._run(function (v) fn(emit, v) end)
    end)
end

function Flow:debounce(ms)
    local up = self
    return new_flow(function (emit)
        async.scope(function (scope)
            local ch = async.channel(0)
            scope:launch(function ()
                up._run(function (v) ch:send(v) end)
                ch:close()
            end)
            ch:debounce(ms):each(emit)
        end)
    end)
end

function Flow:distinct_until_changed(key, are_equal)
    key = key or function (x) return x end
    are_equal = are_equal or function (a, b) return a == b end
    local up = self
    return new_flow(function (emit)
        local prev = nil
        local has = false
        up._run(function (v)
            local k = key(v)
            if not has then
                has = true; prev = k; emit(v)
            else
                if not are_equal(prev, k) then
                    prev = k; emit(v)
                end
            end
        end)
    end)
end

function Flow:flow_on(ctx)
    local up = self
    return new_flow(function (emit)
        async.with_context(ctx, function ()
            up._run(emit)
        end)
    end)
end

function Flow:buffer(cap)
    local up = self
    return new_flow(function (emit)
        async.scope(function (scope)
            local ch = async.channel(cap or 0)
            scope:launch(function ()
                up._run(function (v) ch:send(v) end)
                ch:close()
            end)
            for v in ch:iter() do emit(v) end
        end)
    end)
end

function Flow:catch(handler)
    local up = self
    return new_flow(function (emit)
        local ok, err = pcall(function () up._run(emit) end)
        if not ok then
            if rawequal(err, BREAK) then error(err) end
            handler(emit, err)
        end
    end)
end

-- deferred operators
function Flow:flat_map_concat(fn)
    local up = self
    return new_flow(function (emit)
        up._run(function (v)
            local inner = fn(v)
            inner._run(emit)
        end)
    end)
end

function Flow:flat_map_latest(fn)
    local up = self
    return new_flow(function (emit)
        up._run(function (v)
            local inner = fn(v)
            inner._run(emit)
        end)
    end)
end

function Flow:transform_latest(fn)
    local up = self
    return new_flow(function (emit)
        up._run(function (v) fn(emit, v) end)
    end)
end

function Flow:transform_while(fn)
    local up = self
    return new_flow(function (emit)
        local cont = true
        up._run(function (v)
            if not cont then return end
            local r = fn(emit, v)
            if r == false then cont = false end
        end)
    end)
end

function Flow:scan(initial, op)
    local up = self
    return new_flow(function (emit)
        local acc = initial
        emit(acc)
        up._run(function (v)
            acc = op(acc, v)
            emit(acc)
        end)
    end)
end

function Flow:retry(n, predicate)
    n = n or 1
    local up = self
    return new_flow(function (emit)
        local attempts = 0
        while true do
            local ok, err = pcall(function () up._run(emit) end)
            if ok then break end
            attempts = attempts + 1
            if attempts > n then error(err) end
        end
    end)
end

function Flow:chunked(size)
    if type(size) ~= "number" or size <= 0 then
        error("IllegalArgumentException")
    end
    local up = self
    return new_flow(function (emit)
        local chunk = {}
        up._run(function (v)
            table.insert(chunk, v)
            if #chunk >= size then
                emit(chunk); chunk = {}
            end
        end)
        if #chunk > 0 then emit(chunk) end
    end)
end

function Flow:conflate()
    -- no-op in the synchronous model (no backpressure to drop)
    return self
end

function Flow:collect_latest(fn)
    -- synchronous collection: behaves like collect
    self._run(fn)
end

function Flow:zip(other, transform)
    local up = self
    return new_flow(function (emit)
        local a_vals, b_vals = {}, {}
        up._run(function (v) table.insert(a_vals, v) end)
        other._run(function (v) table.insert(b_vals, v) end)
        local n = math.min(#a_vals, #b_vals)
        for i = 1, n do
            if transform then
                emit(transform(a_vals[i], b_vals[i]))
            else
                emit({ a_vals[i], b_vals[i] })
            end
        end
    end)
end

function Flow:combine(other, transform)
    local up = self
    return new_flow(function (emit)
        local b_vals = {}
        other._run(function (v) table.insert(b_vals, v) end)
        local bi = 1
        up._run(function (a)
            local b = b_vals[bi] or b_vals[#b_vals]
            if b ~= nil or #b_vals > 0 then
                if transform then emit(transform(a, b))
                else emit({ a, b }) end
            end
            bi = bi + 1
        end)
    end)
end

function flow.merge(flows)
    return new_flow(function (emit)
        async.supervisor_scope(function (scope)
            local ch = async.channel(16)
            local remaining = #flows
            if remaining == 0 then ch:close() end
            for _, f in ipairs(flows) do
                scope:launch(function ()
                    f._run(function (v) ch:send(v) end)
                    remaining = remaining - 1
                    if remaining <= 0 then ch:close() end
                end)
            end
            for v in ch:iter() do emit(v) end
        end)
    end)
end

function Flow:merge(other)
    return flow.merge({ self, other })
end

function Flow:flat_map_merge(fn)
    local up = self
    return new_flow(function (emit)
        async.supervisor_scope(function (scope)
            local ch = async.channel(16)
            scope:launch(function ()
                up._run(function (v)
                    local inner = fn(v)
                    inner._run(function (iv) ch:send(iv) end)
                end)
                ch:close()
            end)
            for v in ch:iter() do emit(v) end
        end)
    end)
end

-- ---------- SharedFlow / StateFlow ----------

local function make_shared_flow(sf)
    return new_flow(function (emit)
        local ch = async.channel(sf._replay + sf._extra + 1)
        for _, v in ipairs(sf._replay_buffer) do
            ch:send(v)
        end
        table.insert(sf._subscribers, ch)
        local ok, err = pcall(function ()
            for v in ch:iter() do emit(v) end
        end)
        -- unregister
        for i, c in ipairs(sf._subscribers) do
            if c == ch then table.remove(sf._subscribers, i); break end
        end
        if not ok and not rawequal(err, BREAK) then
            error(err, 0)
        end
    end)
end

function flow.mutable_shared_flow(replay, extra, on_overflow)
    replay = replay or 0
    extra = extra or 0
    local sf = {
        _replay = replay,
        _extra = extra,
        _on_overflow = on_overflow or "SUSPEND",
        _replay_buffer = {},
        _subscribers = {},
    }
    function sf:emit(value)
        table.insert(self._replay_buffer, value)
        while #self._replay_buffer > self._replay do
            table.remove(self._replay_buffer, 1)
        end
        for _, ch in ipairs(self._subscribers) do
            if self._on_overflow == "DROP_LATEST" then
                -- best-effort: try send, drop if full
                local ok = pcall(function () ch:send(value) end)
                if not ok then end
            else
                ch:send(value)
            end
        end
    end
    function sf:try_emit(value)
        -- returns true if emitted without suspension
        local ok = pcall(function () self:emit(value) end)
        return ok
    end
    local f = make_shared_flow(sf)
    sf._flow = f
    sf._run = f._run
    setmetatable(sf, { __index = Flow })
    sf.as_shared_flow = function () return f end
    return sf
end

function flow.mutable_state_flow(initial)
    local sf = flow.mutable_shared_flow(1, 0, "DROP_OLDEST")
    -- seed replay buffer
    sf._replay_buffer = { initial }
    local state = { _sf = sf, _value = initial, value = initial }
    function state:get_value()
        return self.value
    end
    function state:set_value(v)
        self.value = v
        self._value = v
        sf._replay_buffer = { v }
        for _, ch in ipairs(sf._subscribers) do
            pcall(function () ch:send(v) end)
        end
    end
    function state:update(fn)
        self:set_value(fn(self:get_value()))
    end
    function state:compare_and_set(old, new)
        if self:get_value() == old then
            self:set_value(new)
            return true
        end
        return false
    end
    -- make it a Flow
    state._flow = make_shared_flow(sf)
    state._run = state._flow._run
    setmetatable(state, { __index = Flow })
    return state
end

flow.Flow = Flow
return flow, Flow