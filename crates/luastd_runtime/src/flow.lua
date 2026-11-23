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

function flow.of_one(value)
    return new_flow(function (emit)
        emit(value)
    end)
end

function Flow:collect(fn)
    self._run(fn)
end

function Flow:to_list()
    local acc = {}
    self._run(function (v) table.insert(acc, v) end)
    return acc
end

function Flow:first()
    local result = nil
    local found = false
    local ok, err = pcall(function ()
        self._run(function (v)
            if not found then
                result = v
                found = true
                error(BREAK)
            end
        end)
    end)
    if not ok and not rawequal(err, BREAK) then
        error(err, 0)
    end
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

function Flow:take(n)
    local up = self
    return new_flow(function (emit)
        local count = 0
        local ok, err = pcall(function ()
            up._run(function (v)
                if count >= n then error(BREAK) end
                count = count + 1
                emit(v)
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

function Flow:retry(n)
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

flow.Flow = Flow
return flow, Flow