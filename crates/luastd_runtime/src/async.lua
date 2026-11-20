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

local function run_scope(kind, body, ms, coroutine_name, parent)
    local handle = core.enter(kind, coroutine_name, parent)
    if ms then core.timeout(handle, ms) end
    local result = pack(raw_pcall(body, wrap_scope(handle)))
    local status, err = finish(handle, result)
    if status == "ok" then return unpack(result, 2, result.n) end
    if status == "failed" then error(err, 0) end
    if status == "timeout" then
        local name = core.coroutine_name(handle)
        local message = ("Timed out waiting for %s ms"):format(tostring(ms))
        if name then
            message = ('Coroutine "%s" %s'):format(name, message:sub(1, 1):lower() .. message:sub(2))
        end
        error(new_error("Timeout", message), 0)
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

local function launch(parent, context, body)
    local elements = context or {}
    local job = elements.job
    return wrap_job(core.spawn(job and job._handle or parent, "launch", body, elements.name))
end

function Scope:launch(context_or_body, body)
    local context
    context, body = launch_arguments(context_or_body, body, "launch")
    return launch(self._handle, context, body)
end

function Scope:async(body)
    check_fn(body, 1, "async")
    return wrap_job(core.spawn(self._handle, "async", body, nil))
end

function Job:cancel()
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
    return launch(core.current(), context, body)
end

async["async"] = function (body)
    check_fn(body, 1, "async")
    return wrap_job(core.spawn(core.current(), "async", body, nil))
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
    return run_scope("timeout", body, ms)
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

function async.is_active()
    return core.active()
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

--- The implementation behind the `luastd.async.Channel` stub.
---@class luastd.async.ChannelImpl
---@field _channel  any  core channel userdata
---@field _producer any? the producer job's handle, for `produce` channels
local Channel = {}
Channel.__index = Channel

function async.channel(cap)
    if cap == nil then cap = 0 end
    if type(cap) ~= "number" or cap < 0 or cap % 1 ~= 0 then
        error(
            new_error(
                "InvalidArgument",
                ("bad argument #1 to 'channel' (non-negative integer expected, got %s)"):format(tostring(cap))
            ), 2
        )
    end
    return setmetatable({ _channel = core.channel(cap) }, Channel)
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
        error(new_error("ChannelClosed", "send on a closed channel"), 2)
    end
end

function Channel:receive()
    local status, value = core.receive(self._channel)
    if status == "value" then return value end
    if status == "cancelled" then raise_cancelled() end
    error(new_error("ChannelClosed", "receive on a closed, empty channel"), 2)
end

function Channel:close()
    core.close(self._channel)
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
            local status, value = core.receive(channel)
            if status == "cancelled" then raise_cancelled() end
            if status ~= "value" then return end
            if fn(value) == false then return end
        end
    end, function () self:cancel() end)
end

function Channel:is_closed()
    return core.is_closed(self._channel)
end

function Channel:iter()
    local channel = self._channel
    return function ()
        local status, value = core.receive(channel)
        if status == "value" then return value end
        if status == "cancelled" then raise_cancelled() end
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
                        if next_status == "closed" then return end
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

return async, pcall, xpcall
