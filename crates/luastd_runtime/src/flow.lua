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
    local result = new_flow(function (emit)
        body(function (value)
            async.ensure_active()
            emit(value)
        end)
    end)
    result._cancellable = true
    return result
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
    self._run(function (v)
            result = v
            found = true
        end)
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

local function short_circuit(self, pred, initial, stop_when_match, terminal)
    local result = initial
    local stop = {}
    local ok, err = pcall(function ()
        self._run(function (v)
            local matches = not not pred(v)
            if matches == stop_when_match then
                result = terminal
                error(stop, 0)
            end
        end)
    end)
    if not ok and not rawequal(err, stop) then error(err, 0) end
    return result
end

function Flow:all(pred)
    return short_circuit(self, pred, true, false, false)
end

function Flow:any(pred)
    return short_circuit(self, pred, false, true, true)
end

function Flow:none(pred)
    return short_circuit(self, pred, true, true, false)
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
        if first then
            acc = v
            first = false
        else
            acc = op(acc, v)
        end
    end)
    if first then error("reduce on empty flow") end
    return acc
end

function Flow:associate(transform)
    return self:associate_to({}, transform)
end

function Flow:associate_to(target, transform)
    self._run(function (value)
        local key, mapped = transform(value)
        target[key] = mapped
    end)
    return target
end

function Flow:associate_by(key_selector, value_transform)
    return self:associate_by_to({}, key_selector, value_transform)
end

function Flow:associate_by_to(target, key_selector, value_transform)
    self._run(function (value)
        local key = key_selector(value)
        local mapped
        if value_transform then
            mapped = value_transform(value)
        else
            mapped = value
        end
        target[key] = mapped
    end)
    return target
end

function Flow:associate_with(value_transform)
    return self:associate_with_to({}, value_transform)
end

function Flow:associate_with_to(target, value_transform)
    self._run(function (value)
        target[value] = value_transform(value)
    end)
    return target
end

function Flow:group_by(key_selector, value_transform)
    return self:group_by_to({}, key_selector, value_transform)
end

function Flow:group_by_to(target, key_selector, value_transform)
    self._run(function (value)
        local key = key_selector(value)
        local mapped
        if value_transform then
            mapped = value_transform(value)
        else
            mapped = value
        end
        local group = target[key]
        if group == nil then
            group = {}
            target[key] = group
        end
        table.insert(group, mapped)
    end)
    return target
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
            if count < n then
                count = count + 1
            else
                emit(v)
            end
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
                has = true
                prev = k
                emit(v)
            else
                if not are_equal(prev, k) then
                    prev = k
                    emit(v)
                end
            end
        end)
    end)
end

local function buffered(base, capacity, is_default)
    local result = new_flow(function (emit)
        async.scope(function (scope)
            local ch = async.channel(capacity)
            scope:launch(function ()
                base._run(function (v) ch:send(v) end)
                ch:close()
            end)
            for v in ch:iter() do
                emit(v)
            end
        end)
    end)
    result._buffer_base = base
    result._buffer_capacity = capacity
    result._buffer_default = is_default
    return result
end

function Flow:flow_on(ctx)
    local up = self
    if up._buffer_base then
        local base = new_flow(function (emit)
            async.with_context(ctx, function ()
                up._buffer_base._run(emit)
            end)
        end)
        return buffered(base, up._buffer_capacity, up._buffer_default)
    end
    return new_flow(function (emit)
        async.with_context(ctx, function ()
            up._run(emit)
        end)
    end)
end

function Flow:cancellable()
    if self._cancellable then return self end
    local up = self
    local result = new_flow(function (emit)
        up._run(function (value)
            async.ensure_active()
            emit(value)
        end)
    end)
    result._cancellable = true
    return result
end

function Flow:buffer(cap)
    local base = self._buffer_base or self
    local previous_capacity = self._buffer_capacity
    local previous_default = self._buffer_default
    local is_default = cap == nil and (previous_capacity == nil or previous_default)
    local capacity
    if previous_capacity == nil then
        capacity = cap == nil and 64 or cap
    elseif previous_default and cap == nil then
        capacity = 64
    elseif previous_default then
        capacity = cap
    elseif cap == nil then
        capacity = previous_capacity
    else
        capacity = previous_capacity + cap
    end
    return buffered(base, capacity, is_default)
end

function Flow:catch(handler)
    local up = self
    return new_flow(function (emit)
        local downstream_failure = {}
        local downstream_error
        local downstream_failed = false
        local ok, err = pcall(function ()
            up._run(function (value)
                local emit_ok, emit_err = pcall(function () emit(value) end)
                if not emit_ok then
                    downstream_failed = true
                    downstream_error = emit_err
                    error(downstream_failure, 0)
                end
            end)
        end)
        if not ok and rawequal(err, downstream_failure) then
            error(downstream_error, 0)
        end
        if downstream_failed then
            if not ok then error(err, 0) end
            error(downstream_error, 0)
        end
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
            local downstream_failure = {}
            local downstream_error
            local downstream_failed = false
            local ok, err = pcall(function ()
                up._run(function (value)
                    local emit_ok, emit_err = pcall(function () emit(value) end)
                    if not emit_ok then
                        downstream_failed = true
                        downstream_error = emit_err
                        error(downstream_failure, 0)
                    end
                end)
            end)
            if not ok and rawequal(err, downstream_failure) then error(downstream_error, 0) end
            if downstream_failed then
                if not ok then error(err, 0) end
                error(downstream_error, 0)
            end
            if ok then break end
            attempts = attempts + 1
            if attempts > n or (predicate and not predicate(err)) then error(err, 0) end
        end
    end)
end

function Flow:retry_when(predicate)
    local up = self
    return new_flow(function (emit)
        local attempt = 0
        while true do
            local downstream_failure = {}
            local downstream_error
            local downstream_failed = false
            local ok, err = pcall(function ()
                up._run(function (value)
                    local emit_ok, emit_err = pcall(function () emit(value) end)
                    if not emit_ok then
                        downstream_failed = true
                        downstream_error = emit_err
                        error(downstream_failure, 0)
                    end
                end)
            end)
            if not ok and rawequal(err, downstream_failure) then error(downstream_error, 0) end
            if downstream_failed then
                if not ok then error(err, 0) end
                error(downstream_error, 0)
            end
            if ok then break end
            if not predicate(err, attempt) then error(err, 0) end
            attempt = attempt + 1
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
                emit(chunk)
                chunk = {}
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
        local absent = {}
        local nil_value = {}
        async.scope(function (scope)
            local events = async.channel(async.RENDEZVOUS)
            local remaining = 2
            local latest = { absent, absent }
            local jobs = {}
            local function launch_source(source, index)
                jobs[index] = scope:launch(function ()
                    source._run(function (value)
                        events:send({ index = index, value = value == nil and nil_value or value })
                        async.yield()
                    end)
                    events:send({ index = index, done = true })
                    remaining = remaining - 1
                    if remaining == 0 then events:close() end
                end)
            end
            launch_source(up, 1)
            launch_source(other, 2)
            for event in events:iter() do
                if event.done then
                    if latest[event.index] == absent then
                        local other_job = jobs[3 - event.index]
                        if other_job then other_job:cancel() end
                        break
                    end
                else
                    latest[event.index] = event.value
                    if latest[1] ~= absent and latest[2] ~= absent then
                        local a, b = latest[1], latest[2]
                        if a == nil_value then a = nil end
                        if b == nil_value then b = nil end
                        if transform then
                            emit(transform(a, b))
                        else
                            emit({ a, b })
                        end
                    end
                end
            end
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
            for v in ch:iter() do
                emit(v)
            end
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
            for v in ch:iter() do
                emit(v)
            end
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
            for v in ch:iter() do
                emit(v)
            end
        end)
        -- unregister
        for i, c in ipairs(sf._subscribers) do
            if c == ch then
                table.remove(sf._subscribers, i)
                break
            end
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
        _subscribers = {}
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
