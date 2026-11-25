-- luastd.async: the Lua half of structured concurrency (ADR 0003, 0005).
-- The Rust core (scheduler.rs) owns jobs, tokens and channels; this file owns
-- every user-facing function, so error values (tables, the cancellation
-- sentinel) are raised from Lua and never lose their identity in a Rust frame.

-- Job bodies run in coroutines the scheduler drives, so they may suspend.
---@diagnostic disable: await-in-sync

local core, raw_pcall, raw_xpcall = ...
local CANCELLED = core.CANCELLED
---@diagnostic disable-next-line: undefined-global, deprecated
local unpack = table.unpack or unpack

local function pack(...)
    return { n = select("#", ...), ... }
end

local function raise_cancelled()
    error(CANCELLED, 0)
end

local function new_error(kind, message)
    return core.new_error(kind, message)
end

local function check_fn(value, index, name)
    if type(value) ~= "function" then
        error(
            new_error(
                "InvalidArgument",
                ("bad argument #%d to '%s' (function expected, got %s)"):format(index, name, type(value))
            ), 3
        )
    end
end

local function check_ms(value, index, name)
    if type(value) ~= "number" or value ~= value or value < 0 then
        error(new_error(
                "InvalidArgument",
                ("bad argument #%d to '%s' (non-negative number of milliseconds expected, got %s)")
                    :format(index, name, tostring(value))
            ), 3)
    end
end

-- pcall / xpcall that never swallow cancellation (ADR 0005).

local function rethrow(ok, ...)
    if not ok and rawequal((...), CANCELLED) then raise_cancelled() end
    return ok, ...
end

local function pcall(f, ...)
    return rethrow(raw_pcall(f, ...))
end

local function xpcall(f, handler, ...)
    return rethrow(raw_xpcall(f, function (err)
            if rawequal(err, CANCELLED) then return err end
            return handler(err)
        end, ...
        ))
end

local async = {}

-- Jobs own lifetime; scopes expose a context and launch child jobs.
local Job = {}
Job.__index = Job
local Scope = {}
Scope.__index = Scope

local function wrap_job(handle)
    return setmetatable({ _handle = handle }, Job)
end

local function wrap_scope(handle)
    return setmetatable({ _handle = handle }, Scope)
end

local coroutine_contexts = setmetatable({}, { __mode = "k" })
local coroutine_names = setmetatable({}, { __mode = "k" })
local completable_channels = setmetatable({}, { __mode = "k" })
local timeout_error_owners = setmetatable({}, { __mode = "k" })

local CoroutineContext = {}
CoroutineContext.__index = CoroutineContext
CoroutineContext.__newindex = function () error("CoroutineContext is immutable", 2) end
local CoroutineName = {}
CoroutineName.__index = function (self, key)
    if key == "name" then return coroutine_names[self] end
    return CoroutineName[key]
end
CoroutineName.__newindex = function () error("CoroutineName is immutable", 2) end
CoroutineName.__tostring = function (self)
    return ("CoroutineName(%s)"):format(coroutine_names[self])
end

local function make_context(job, name)
    local context = setmetatable({}, CoroutineContext)
    coroutine_contexts[context] = { job = job, name = name }
    return context
end

function CoroutineContext:job()
    return coroutine_contexts[self].job
end

function CoroutineContext:coroutine_name()
    return coroutine_contexts[self].name
end

function Scope:coroutine_context()
    return make_context(wrap_job(self._handle), core.coroutine_name(self._handle))
end

local function run_cancel_handlers(handle)
    local handlers = core.take_on_cancel(handle)
    if #handlers == 0 then return end
    core.push_non_cancellable()
    for i = 1, #handlers do
        raw_pcall(handlers[i])
    end
    core.pop_non_cancellable()
end

-- Settle a finished body: wait for children, run on_cancel handlers when it
-- did not complete normally, then record the result and wake joiners.
local function finish(handle, result)
    local status, err = core.settle(handle, result[1], result[2])
    if status ~= "ok" then run_cancel_handlers(handle) end
    core.complete(handle, status, status == "ok" and result or err)
    return status, err
end

-- The main function of every job's coroutine; the callback receives a scope.
core.set_runner(function (handle, body)
    local _, cancelled = core.state(handle)
    local result
    if cancelled then
        result = pack(false, CANCELLED) -- launched into a finished or cancelled scope
    else
        result = pack(raw_pcall(body, wrap_scope(handle)))
    end
    finish(handle, result)
end)

local function run_scope(kind, body, ms, coroutine_name, parent, timeout_owner)
    local handle = core.enter(kind, coroutine_name, parent)
    if ms then core.timeout(handle, ms) end
    local result
    if core.active() then
        result = pack(raw_pcall(body, wrap_scope(handle)))
    else
        -- Structured builders inherit an already-cancelled parent and must
        -- not enter user code before reporting cancellation.
        result = pack(false, CANCELLED)
    end
    local status, err = finish(handle, result)
    if status == "ok" then return unpack(result, 2, result.n) end
    if status == "failed" then error(err, 0) end
    if status == "timeout" then
        local name = core.coroutine_name(handle)
        local message = ("Timed out waiting for %s ms"):format(tostring(ms))
        if name then
            message = ('Coroutine "%s" %s'):format(name, message:sub(1, 1):lower() .. message:sub(2))
        end
        local err = new_error("Timeout", message)
        if timeout_owner then timeout_error_owners[err] = timeout_owner end
        error(err, 0)
    end
    raise_cancelled()
end

local function launch_arguments(context_or_body, body, name)
    if body == nil then
        check_fn(context_or_body, 1, name)
        return nil, context_or_body
    end
    if getmetatable(context_or_body) ~= CoroutineContext then
        error(new_error("InvalidArgument", ("bad argument #1 to '%s' (CoroutineContext expected)"):format(name)), 3)
    end
    check_fn(body, 2, name)
    return coroutine_contexts[context_or_body], body
end

local function launch(parent, context, body, lazy)
    local elements = context or {}
    local job = elements.job
    return wrap_job(core.spawn(job and job._handle or parent, "launch", body, elements.name, lazy and true or false))
end

function Scope:launch(context_or_body, body)
    local context
    context, body = launch_arguments(context_or_body, body, "launch")
    return launch(self._handle, context, body, false)
end

function Scope:launch_lazy(context_or_body, body)
    local context
    context, body = launch_arguments(context_or_body, body, "launch_lazy")
    return launch(self._handle, context, body, true)
end

function Scope:async(body)
    check_fn(body, 1, "async")
    return wrap_job(core.spawn(self._handle, "async", body, nil))
end

function Job:cancel()
    if completable_channels[self._handle] then
        core.cancel(self._handle)
        return true
    end
    core.cancel(self._handle)
end

function Job:is_active()
    local active = core.state(self._handle)
    return active
end

function Job:is_cancelled()
    local _, cancelled = core.state(self._handle)
    return cancelled
end

function Job:is_completed()
    local _, _, done = core.state(self._handle)
    return done
end

function Job:start()
    return core.start_job(self._handle)
end

function Job:complete(value)
    local ch = completable_channels[self._handle]
    if not ch then return false end
    local status = core.send(ch._channel, { ok = true, value = value })
    return status == "ok"
end

function Job:complete_exceptionally(err)
    local ch = completable_channels[self._handle]
    if not ch then return false end
    local status = core.send(ch._channel, { ok = false, err = err })
    return status == "ok"
end

function Job:on_cancel(handler)
    check_fn(handler, 1, "on_cancel")
    core.on_cancel(self._handle, handler)
end

-- Keep the existing scope conveniences while exposing the distinct Job
-- through `scope:coroutine_context():job()`.
Scope.cancel = Job.cancel
Scope.is_active = Job.is_active
Scope.is_cancelled = Job.is_cancelled
Scope.is_completed = Job.is_completed
Scope.on_cancel = Job.on_cancel
Scope.start = Job.start
Scope.complete = Job.complete
Scope.complete_exceptionally = Job.complete_exceptionally

-- Waiting is prefix-only (`async.join`, `async.await`, `async.try_await`;
-- ADR 0007). Scope is accepted for compatibility, though context:job() is the
-- explicit Job handle in the Kotlin-shaped model.

local function check_job(value, name)
    local mt = getmetatable(value)
    if mt ~= Job and mt ~= Scope then
        error(
            new_error("InvalidArgument", ("bad argument #1 to '%s' (job expected, got %s)"):format(name, type(value))),
            3
        )
    end
end

-- Wait for `job`; a cancelled caller raises the cancellation, even when the
-- job has already finished (every wait is a cancellation point).
local function wait(job)
    -- Lazy jobs start on first wait, matching Kotlin's await/join semantics.
    if not job:is_completed() then job:start() end
    if not core.join(job._handle) then raise_cancelled() end
end

-- `true, values...` or `false, err` for a finished job.
local function outcome(job)
    local status, value = core.result(job._handle)
    if status == "ok" then return true, unpack(value, 2, value.n) end
    if status == "failed" then return false, value end
    return false, new_error("JobCancelled", "the awaited job was cancelled")
end

local function raise_outcome(ok, ...)
    if not ok then error((...), 0) end
    return ...
end

function async.join(job)
    check_job(job, "join")
    wait(job)
end

function async.join_all(...)
    local jobs = pack(...)
    for i = 1, jobs.n do
        check_job(jobs[i], "join_all")
    end
    for i = 1, jobs.n do
        wait(jobs[i])
    end
end

function async.await(deferred)
    check_job(deferred, "await")
    wait(deferred)
    return raise_outcome(outcome(deferred))
end

function async.try_await(deferred)
    check_job(deferred, "try_await")
    wait(deferred)
    return outcome(deferred)
end

function async.await_all(...)
    local deferreds, values = pack(...), {}
    for i = 1, deferreds.n do
        check_job(deferreds[i], "await_all")
        wait(deferreds[i])
        values[i] = (raise_outcome(outcome(deferreds[i])))
    end
    return unpack(values, 1, deferreds.n)
end

function async.launch(context_or_body, body)
    local context
    context, body = launch_arguments(context_or_body, body, "launch")
    return launch(core.current(), context, body, false)
end

function async.launch_lazy(context_or_body, body)
    local context
    context, body = launch_arguments(context_or_body, body, "launch_lazy")
    return launch(core.current(), context, body, true)
end

async["async"] = function (body)
    check_fn(body, 1, "async")
    return wrap_job(core.spawn(core.current(), "async", body, nil))
end

function async.async_lazy(body)
    check_fn(body, 1, "async_lazy")
    return wrap_job(core.spawn(core.current(), "async", body, nil, true))
end

function async.completable_deferred()
    local channel = async.channel(1)
    local job = async.async(function (scope)
        return async.finally(function ()
            local record = channel:receive()
            if record.cancelled then raise_cancelled() end
            if not record.ok then error(record.err, 0) end
            return record.value
        end,
            function ()
                channel:close()
            end)
    end)
    completable_channels[job._handle] = channel
    return job
end

function async.scope(body)
    check_fn(body, 1, "scope")
    return run_scope("scope", body)
end

function async.try_scope(body)
    check_fn(body, 1, "try_scope")
    -- The module's `pcall` rethrows cancellation (ADR 0005).
    return pcall(run_scope, "scope", body)
end

function async.supervisor_scope(body)
    check_fn(body, 1, "supervisor_scope")
    return run_scope("supervisor", body)
end

function async.with_timeout(ms, body)
    if type(ms) ~= "number" or ms ~= ms then
        error(
            new_error(
                "InvalidArgument",
                ("bad argument #1 to 'with_timeout' (number of milliseconds expected, got %s)"):format(tostring(ms))
            ), 2
        )
    end
    check_fn(body, 2, "with_timeout")
    -- As in kotlinx.coroutines: no time at all times out before the body runs.
    if ms <= 0 then error(new_error("Timeout", "Timed out immediately"), 0) end
    return run_scope("timeout", body, ms, nil, nil, {})
end

function async.with_timeout_or_null(ms, body)
    if type(ms) ~= "number" or ms ~= ms then
        error(
            new_error(
                "InvalidArgument",
                ("bad argument #1 to 'with_timeout_or_null' (number of milliseconds expected, got %s)"):format(
                    tostring(ms)
                )
            ), 2
        )
    end
    check_fn(body, 2, "with_timeout_or_null")
    if ms <= 0 then return nil end

    local owner = {}
    local result = pack(raw_pcall(run_scope, "timeout", body, ms, nil, nil, owner))
    if result[1] then return unpack(result, 2, result.n) end
    local err = result[2]
    if rawequal(err, CANCELLED) then raise_cancelled() end
    if timeout_error_owners[err] == owner then return nil end
    error(err, 0)
end

function async.coroutine_name(name)
    if type(name) ~= "string" then
        error(new_error("InvalidArgument", "bad argument #1 to 'coroutine_name' (string expected)"), 2)
    end
    local element = setmetatable({}, CoroutineName)
    coroutine_names[element] = name
    return element
end

function async.context(...)
    local job, name
    for i = 1, select("#", ...) do
        local element = select(i, ...)
        local mt = getmetatable(element)
        if mt == CoroutineName then
            name = coroutine_names[element]
        elseif mt == Job then
            job = element
        elseif mt == CoroutineContext then
            local context = coroutine_contexts[element]
            job = context.job or job
            name = context.name or name
        else
            error(new_error("InvalidArgument", "context elements must be a Job, CoroutineName, or CoroutineContext"), 2)
        end
    end
    return make_context(job, name)
end

function async.supervisor_job()
    return wrap_job(core.supervisor_job())
end

function async.with_context(context, body)
    if getmetatable(context) ~= CoroutineContext then
        error(new_error("InvalidArgument", "bad argument #1 to 'with_context' (CoroutineContext expected)"), 2)
    end
    check_fn(body, 2, "with_context")
    local elements = coroutine_contexts[context]
    return run_scope("scope", body, nil, elements.name, elements.job and elements.job._handle)
end

function async.current_context()
    local job = wrap_job(core.current())
    return make_context(job, core.coroutine_name(job._handle))
end

function async.delay(ms)
    check_ms(ms, 1, "delay")
    if not core.delay(ms) then raise_cancelled() end
end

function async.yield()
    if not core.yield() then raise_cancelled() end
end

function async.await_cancellation()
    core.await_cancellation()
    raise_cancelled()
end

function async.is_active()
    return core.active()
end

function async.ensure_active()
    if not core.active() then raise_cancelled() end
end

function async.current()
    return wrap_scope(core.current())
end

function async.is_cancellation(err)
    return rawequal(err, CANCELLED)
end

function async.finally(body, cleanup)
    check_fn(body, 1, "finally")
    check_fn(cleanup, 2, "finally")
    local result = pack(raw_pcall(body))
    core.push_non_cancellable()
    local cleaned = pack(raw_pcall(cleanup))
    core.pop_non_cancellable()
    if not result[1] then error(result[2], 0) end
    if not cleaned[1] then error(cleaned[2], 0) end
    return unpack(result, 2, result.n)
end

-- Channels.

async.RENDEZVOUS = 0
async.UNLIMITED = -1
async.CONFLATED = -2

--- The implementation behind the `luastd.async.Channel` stub.
---@class luastd.async.ChannelImpl
---@field _channel  any  core channel userdata
---@field _producer any? the producer job's handle, for `produce` channels
local Channel = {}
Channel.__index = Channel

function async.channel(cap, overflow)
    if cap == nil then cap = 0 end
    if type(cap) ~= "number" or (cap < -2 or cap % 1 ~= 0) then
        error(
            new_error(
                "InvalidArgument",
                ("bad argument #1 to 'channel' (non-negative integer or channel constant expected, got %s)"):format(
                    tostring(cap)
                )
            ), 2
        )
    end
    if cap == -1 then cap = 2147483647 end
    if cap == -2 then
        if overflow ~= nil then
            error(new_error("InvalidArgument", "conflated channels do not accept an overflow mode"), 2)
        end
        cap = 1
        overflow = "conflated"
    end
    if overflow == nil then overflow = "suspend" end
    if overflow ~= "suspend" and overflow ~= "drop_oldest" and overflow ~= "drop_latest" and overflow ~= "conflated" then
        error(new_error("InvalidArgument", ("invalid channel overflow mode %s"):format(tostring(overflow))), 2)
    end
    return setmetatable({ _channel = core.channel(cap, overflow) }, Channel)
end

function Channel:send(value)
    if value == nil then
        error(new_error("InvalidArgument", "bad argument #1 to 'send' (cannot send nil)"), 2)
    end
    local status = core.send(self._channel, value)
    if status == "cancelled" then raise_cancelled() end
    if status == "channel_cancelled" then
        -- The consumer is gone: stop the sender quietly, as a cancellation.
        core.cancel_current()
        raise_cancelled()
    end
    if status == "closed" then
        local reason = core.close_reason(self._channel)
        if reason ~= nil then error(reason, 0) end
        error(new_error("ChannelClosed", "send on a closed channel"), 2)
    end
end

--- Try to send without waiting.
---@param value any
---@return boolean, luastd.Error?
function Channel:try_send(value)
    if value == nil then
        error(new_error("InvalidArgument", "bad argument #1 to 'try_send' (cannot send nil)"), 2)
    end
    local status = core.try_send(self._channel, value)
    if status == "ok" then return true end
    if status == "full" then
        return false, new_error("ChannelFull", "channel is full")
    end
    local reason = core.close_reason(self._channel)
    if reason ~= nil then return false, reason end
    return false, new_error("ChannelClosed", "send on a closed channel")
end

--- Try to receive without waiting.
---@return boolean, any, luastd.Error?
function Channel:try_receive()
    local status, value, reason = core.try_receive(self._channel)
    if status == "value" then return true, value end
    if status == "cancelled" then raise_cancelled() end
    if status == "empty" then return false, nil, new_error("ChannelEmpty", "channel is empty") end
    if reason ~= nil then return false, nil, reason end
    return false, nil, new_error("ChannelClosed", "receive on a closed, empty channel")
end

function Channel:receive()
    local status, value, reason = core.receive(self._channel)
    if status == "value" then return value end
    if status == "cancelled" then raise_cancelled() end
    if reason ~= nil then error(reason, 0) end
    error(new_error("ChannelClosed", "receive on a closed, empty channel"), 2)
end

function Channel:close(cause)
    core.close(self._channel, cause)
end

function Channel:cancel()
    core.cancel_channel(self._channel)
    if self._producer then core.cancel(self._producer) end
end

function Channel:each(fn)
    check_fn(fn, 1, "each")
    local channel = self._channel
    async.finally(function ()
        while true do
            local status, value, reason = core.receive(channel)
            if status == "cancelled" then raise_cancelled() end
            if status ~= "value" then
                if reason ~= nil then error(reason, 0) end
                return
            end
            if fn(value) == false then return end
        end
    end, function () self:cancel() end)
end

function Channel:is_closed()
    return core.is_closed(self._channel)
end

function Channel:is_closed_for_receive()
    return core.is_closed_for_receive(self._channel)
end

function Channel:is_empty()
    return core.is_empty(self._channel)
end

function Channel:iter()
    local channel = self._channel
    return function ()
        local status, value, reason = core.receive(channel)
        if status == "value" then return value end
        if status == "cancelled" then raise_cancelled() end
        if reason ~= nil then error(reason, 0) end
        return nil
    end
end

function Channel:debounce(ms)
    check_ms(ms, 1, "debounce")
    local source = self._channel
    ---@type luastd.async.ChannelImpl
    local out = async.channel(0)
    async.launch(function ()
        async.finally(function ()
            while true do
                local status, value = core.receive(source)
                if status == "cancelled" then raise_cancelled() end
                if status ~= "value" then return end
                while true do
                    local next_status, next_value = core.receive(source, ms)
                    if next_status == "value" then
                        value = next_value
                    elseif next_status == "cancelled" then
                        raise_cancelled()
                    else
                        out:send(value)
                        if next_status == "closed" then
                            ---@type any
                            local reason = core.close_reason(source)
                            if reason ~= nil then out:close(reason) end
                            return
                        end
                        break
                    end
                end
            end
        end, function () out:close() end)
    end)
    return out
end

function async.produce(body, cap)
    check_fn(body, 1, "produce")
    local channel = async.channel(cap)
    local job = async.launch(function (scope)
        async.finally(function () body(channel, scope) end, function () channel:close() end)
    end)
    channel._producer = job._handle
    return channel
end

-- Rate limiting.

function async.debounce(ms, fn)
    check_ms(ms, 1, "debounce")
    check_fn(fn, 2, "debounce")
    local scope = core.current()
    ---@type { handle: any, started: boolean }?
    local pending = nil
    return function (...)
        if pending and not pending.started then core.cancel(pending.handle) end
        local args, state = pack(...), { started = false }
        state.handle = core.spawn(scope, "launch", function ()
            async.delay(ms)
            state.started = true
            fn(unpack(args, 1, args.n))
        end, nil
        )
        pending = state
        return wrap_job(state.handle)
    end
end

function async.throttle(ms, fn)
    check_ms(ms, 1, "throttle")
    check_fn(fn, 2, "throttle")
    local last = nil
    return function (...)
        local now = core.now_ms()
        if last == nil or now - last >= ms then
            last = now
            return fn(...)
        end
    end
end

-- Synchronization primitives.

local Semaphore = {}
Semaphore.__index = Semaphore

---@class luastd.async.Mutex
---@field _sem     luastd.async.Semaphore
---@field _owner   any?
---@field _pending any[]
local Mutex = {}
Mutex.__index = Mutex

function async.semaphore(n, acquired)
    if type(n) ~= "number" or n < 0 or n % 1 ~= 0 then
        error(new_error("InvalidArgument", "bad argument #1 to 'semaphore' (non-negative integer expected)"), 2)
    end
    if acquired == nil then acquired = 0 end
    if type(acquired) ~= "number" or acquired < 0 or acquired % 1 ~= 0 or acquired > n then
        error(new_error("InvalidArgument", "bad argument #2 to 'semaphore' (integer in 0..permits expected)"), 2)
    end
    return setmetatable({ _core = core.semaphore(n, acquired) }, Semaphore)
end

function async.mutex(locked)
    if locked ~= nil and type(locked) ~= "boolean" then
        error(new_error("InvalidArgument", "bad argument #1 to 'mutex' (boolean expected)"), 2)
    end
    local sem = async.semaphore(1, locked and 1 or 0)
    return setmetatable({ _sem = sem, _owner = nil, _pending = {} }, Mutex)
end

function Semaphore:acquire()
    core.acquire(self._core)
end

function Semaphore:release()
    core.release(self._core)
end

function Semaphore:try_acquire()
    return core.try_acquire(self._core)
end

function Semaphore:available_permits()
    return core.available_permits(self._core)
end

function Semaphore:is_locked()
    return self:available_permits() == 0
end

function Semaphore:with_permit(body)
    check_fn(body, 1, "with_permit")
    self:acquire()
    async.finally(body, function () self:release() end)
end

-- Mutex.

function Mutex:is_locked()
    return self._sem:available_permits() == 0
end

function Mutex:try_lock(owner)
    if owner ~= nil and self:holds_lock(owner) then
        error(new_error("IllegalState", "This mutex is already locked by the specified owner: " .. tostring(owner)), 2)
    end
    local ok = self._sem:try_acquire()
    if ok then self._owner = owner end
    return ok
end

function Mutex:lock(owner)
    if owner ~= nil and self:holds_lock(owner) then
        error(new_error("IllegalState", "This mutex is already locked by the specified owner: " .. tostring(owner)), 2)
    end
    if self._sem:try_acquire() then
        self._owner = owner
        return
    end
    table.insert(self._pending, owner)
    local ok, err = pcall(function () self._sem:acquire() end)
    for i, v in ipairs(self._pending) do
        if rawequal(v, owner) then
            table.remove(self._pending, i)
            break
        end
    end
    if not ok then error(err, 0) end
    self._owner = owner
end

function Mutex:unlock(owner)
    if not self:is_locked() then
        error(new_error("IllegalState", "This mutex is not locked"), 2)
    end
    if owner ~= nil and not rawequal(self._owner, owner) then
        error(new_error("IllegalState", "This mutex is locked by another owner"), 2)
    end
    -- Transfer ownership to the next waiter synchronously, if any.
    if #self._pending > 0 then
        self._owner = self._pending[1]
        table.remove(self._pending, 1)
    else
        self._owner = nil
    end
    self._sem:release()
end

function Mutex:holds_lock(owner)
    if not self:is_locked() then return false end
    return rawequal(self._owner, owner)
end

function Mutex:acquire(owner)
    self:lock(owner)
end

function Mutex:release(owner)
    self:unlock(owner)
end

function Mutex:with_lock(body)
    check_fn(body, 1, "with_lock")
    self:lock(nil)
    async.finally(body, function () self:unlock(nil) end)
end

return async, pcall, xpcall
