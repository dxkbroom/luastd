-- The harness runs every `it` body inside the spec's coroutine, so they may
-- call `---@async` functions.
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")

---@param fn fun()
---@return any
local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return err
end

describe("luastd.async", function ()
    describe("launch and async", function ()
        it("run concurrently and join", function ()
            local log = {}
            async.scope(function ()
                local a = async.launch(function ()
                    async.delay(20)
                    table.insert(log, "a")
                end)
                async.launch(function () table.insert(log, "b") end)
                async.join(a)
                table.insert(log, "joined")
            end)
            assert.are.same({ "b", "a", "joined" }, log)
        end)

        it("await returns every value", function ()
            local a, b = async.await(async.async(function ()
                    async.delay(5)
                    return 1, 2
                end))
            assert.is_equal(1, a)
            assert.is_equal(2, b)
        end)

        it("has no method forms of await and join (ADR 0007)", function ()
            async.scope(function (scope)
                local d = async.async(function () return 1 end)
                local job = async.launch(function () end)
                assert.is_nil(rawget(getmetatable(d), "await"))
                ---@diagnostic disable: undefined-field
                assert.is_nil(d.await)
                assert.is_nil(job.join)
                assert.is_nil(scope.join)
                assert.is_nil(scope.await)
                ---@diagnostic enable: undefined-field
                async.await(d)
            end)
        end)

        it("await and join reject non-jobs", function ()
            ---@diagnostic disable-next-line: param-type-mismatch
            assert.is_equal("InvalidArgument", error_of(function () async.await({}) end).kind)
            ---@diagnostic disable-next-line: param-type-mismatch
            assert.is_equal("InvalidArgument", error_of(function () async.join(42) end).kind)
            ---@diagnostic disable-next-line: param-type-mismatch
            assert.is_equal("InvalidArgument", error_of(function () async.try_await(nil) end).kind)
        end)

        it("join waits without returning values", function ()
            local done = false
            local job = async.launch(function ()
                async.delay(5)
                done = true
            end)
            async.join(job)
            assert.is_true(done)
            assert.is_true(job:is_completed())
        end)

        it("await_all returns the first value of each, in argument order", function ()
            local slow = async.async(function ()
                async.delay(20)
                return "slow", "dropped"
            end)
            local fast = async.async(function () return "fast" end)
            local a, b = async.await_all(slow, fast)
            assert.is_equal("slow", a)
            assert.is_equal("fast", b)
            assert.is_nil(async.await_all())
        end)

        it("await_all raises the first failure it reaches", function ()
            local err = error_of(function ()
                async.supervisor_scope(function ()
                    local ok = async.async(function () return 1 end)
                    local bad = async.async(function () error({ kind = "Bad" }) end)
                    async.await_all(ok, bad)
                end)
            end)
            assert.is_equal("Bad", err.kind)
        end)

        it("pass the job's own scope to the body", function ()
            local inner_done = false
            async.scope(function ()
                local job = async.launch(function (scope)
                    scope:launch(function ()
                        async.delay(5)
                        inner_done = true
                    end)
                end)
                async.join(job)
                -- join waits for the job's children too
                assert.is_true(inner_done)
            end)
        end)

        it("report state", function ()
            async.scope(function ()
                local job = async.launch(function () async.delay(1000) end)
                assert.is_true(job:is_active())
                job:cancel()
                async.join(job)
                assert.is_true(job:is_cancelled())
                assert.is_true(job:is_completed())
                assert.is_false(job:is_active())
            end)
        end)
    end)

    describe("try_await and try_scope", function ()
        it("try_await returns true and every value", function ()
            local d = async.async(function ()
                return "x", "y"
            end)
            local ok, x, y = async.try_await(d)
            assert.is_true(ok)
            assert.is_equal("x", x)
            assert.is_equal("y", y)
        end)

        it("try_await returns false and the job's luastd.Error", function ()
            async.supervisor_scope(function ()
                local d = async.async(function ()
                    async.with_timeout(0, function () end) -- raises a real luastd.Error
                end)
                local ok, err = async.try_await(d)
                assert.is_false(ok)
                assert.is_equal("Timeout", err.kind)
                assert.is_equal("Timeout: Timed out immediately", tostring(err))
            end)
        end)

        it("try_await returns JobCancelled for a cancelled job", function ()
            async.scope(function ()
                local d = async.async(function () async.delay(1000) end)
                d:cancel()
                local ok, err = async.try_await(d)
                assert.is_false(ok)
                assert.is_equal("JobCancelled", err.kind)
            end)
        end)

        it("try_await does not catch the caller's cancellation", function ()
            local reached = false
            async.scope(function ()
                local slow = async.async(function () async.delay(1000) end)
                local waiter = async.launch(function ()
                    async.try_await(slow)
                    reached = true
                end)
                async.delay(5)
                waiter:cancel()
                slow:cancel()
            end)
            assert.is_false(reached)
        end)

        it("try_await cannot recover a failing child of its own scope", function ()
            local reached = false
            local err = error_of(function ()
                async.scope(function ()
                    local d = async.async(function () error({ kind = "Boom" }) end)
                    async.try_await(d) -- the failure cancels this scope first
                    reached = true
                end)
            end)
            assert.is_equal("Boom", err.kind)
            assert.is_false(reached)
        end)

        it("try_scope returns true and the body's values", function ()
            local ok, a, b = async.try_scope(function ()
                return 1, 2
            end)
            assert.is_true(ok)
            assert.is_equal(1, a)
            assert.is_equal(2, b)
        end)

        it("try_scope returns false and the body's error", function ()
            local ok, err = async.try_scope(function () async.with_timeout(0, function () end) end)
            assert.is_false(ok)
            assert.is_equal("Timeout", err.kind)
        end)

        it("try_scope contains a failing child, so the outer scope continues", function ()
            local sibling_finished, after = false, false
            local ok, err
            async.scope(function ()
                async.launch(function ()
                    async.delay(20)
                    sibling_finished = true
                end)
                ok, err = async.try_scope(function ()
                    local d = async.async(function ()
                        async.delay(5)
                        error({ kind = "Boom" })
                    end)
                    return async.await(d)
                end)
                async.yield() -- still active: the failure did not cancel this scope
                after = true
            end)
            assert.is_false(ok)
            assert.is_equal("Boom", err.kind)
            assert.is_true(after)
            assert.is_true(sibling_finished)
        end)

        it("try_scope does not catch the caller's cancellation", function ()
            local reached = false
            async.scope(function ()
                local job = async.launch(function ()
                    async.try_scope(function () async.delay(1000) end)
                    reached = true
                end)
                async.delay(5)
                job:cancel()
            end)
            assert.is_false(reached)
        end)
    end)

    describe("scope", function ()
        it("waits for its children", function ()
            local done = 0
            async.scope(function ()
                for i = 1, 3 do
                    async.launch(function ()
                        async.delay(i * 5)
                        done = done + 1
                    end)
                end
            end)
            assert.is_equal(3, done)
        end)

        it("cancels siblings when a child fails and raises its error", function ()
            local sibling_finished = false
            local err = error_of(function ()
                async.scope(function ()
                    async.launch(function ()
                        async.delay(1000)
                        sibling_finished = true
                    end)
                    async.launch(function ()
                        async.delay(5)
                        error({ kind = "Boom", message = "boom" })
                    end)
                end)
            end)
            assert.is_equal("Boom", err.kind)
            assert.is_false(sibling_finished)
        end)

        it("cancels children when the body fails", function ()
            local child_finished = false
            local err = error_of(function ()
                async.scope(function ()
                    async.launch(function ()
                        async.delay(1000)
                        child_finished = true
                    end)
                    error("body failed", 0)
                end)
            end)
            assert.is_equal("body failed", err)
            assert.is_false(child_finished)
        end)

        it("returns the body's values", function ()
            assert.is_equal(42, async.scope(function () return 42 end))
        end)
    end)

    describe("supervisor_scope", function ()
        it("isolates failing children", function ()
            local sibling_finished = false
            local failed
            async.supervisor_scope(function ()
                async.launch(function ()
                    async.delay(20)
                    sibling_finished = true
                end)
                failed = async.async(function ()
                    async.delay(5)
                    error("child failed", 0)
                end)
            end)
            assert.is_true(sibling_finished)
            assert.is_equal("child failed", error_of(function () async.await(failed) end))
        end)

        it("still fails when its own body fails", function ()
            assert.is_equal(
                "body",
                error_of(function ()
                    async.supervisor_scope(function () error("body", 0) end)
                end)
            )
        end)
    end)

    describe("cancellation through pcall", function ()
        it("is not caught by pcall", function ()
            local after_pcall, caught = false, false
            async.scope(function ()
                local job = async.launch(function ()
                    local ok = pcall(async.delay, 1000)
                    caught = not ok
                    after_pcall = true
                end)
                async.delay(5)
                job:cancel()
                async.join(job)
                assert.is_true(job:is_cancelled())
            end)
            assert.is_false(caught)
            assert.is_false(after_pcall)
        end)

        it("is not caught by nested pcall", function ()
            local reached = false
            async.scope(function ()
                local job = async.launch(function ()
                    pcall(function ()
                        pcall(function () async.delay(1000) end)
                        reached = true
                    end)
                    reached = true
                end)
                async.delay(5)
                job:cancel()
            end)
            assert.is_false(reached)
        end)

        it("skips the xpcall handler", function ()
            local handled, reached = false, false
            async.scope(function ()
                local job = async.launch(function ()
                    xpcall(async.delay, function (e)
                        handled = true
                        return e
                    end, 1000
                    )
                    reached = true
                end)
                async.delay(5)
                job:cancel()
            end)
            assert.is_false(handled)
            assert.is_false(reached)
        end)

        it("leaves ordinary errors to pcall, tables intact", function ()
            assert.is_equal("Mine", error_of(function () error({ kind = "Mine" }) end).kind)
            local ok2, msg = xpcall(error, function (e) return "handled " .. e end, "x", 0)
            assert.is_false(ok2)
            assert.is_equal("handled x", msg)
        end)

        it("is recognisable", function ()
            async.scope(function ()
                local seen
                local job = async.launch(function ()
                    async.finally(function () async.delay(1000) end, function () end)
                end)
                async.delay(5)
                job:cancel()
                async.join(job)
                seen = job:is_cancelled()
                assert.is_true(seen)
            end)
            assert.is_false(async.is_cancellation("Cancelled"))
        end)
    end)

    describe("with_timeout", function ()
        it("returns the body's values in time", function ()
            assert.is_equal("fast", async.with_timeout(100, function () return "fast" end))
        end)

        it("raises a catchable Timeout and cancels the body", function ()
            local finished = false
            local err = error_of(function ()
                async.with_timeout(10, function ()
                    async.launch(function ()
                        async.delay(1000)
                        finished = true
                    end)
                    async.delay(1000)
                    finished = true
                end)
            end)
            assert.is_equal("Timeout", err.kind)
            assert.is_equal("Timed out waiting for 10 ms", err.message)
            assert.is_false(finished)
        end)

        it("cannot be swallowed by pcall inside the body", function ()
            local reached = false
            local err = error_of(function ()
                async.with_timeout(10, function ()
                    pcall(async.delay, 1000)
                    reached = true
                end)
            end)
            assert.is_equal("Timeout", err.kind)
            assert.is_false(reached)
        end)

        it("times out immediately for zero or negative ms without running the body", function ()
            for _, ms in ipairs({ 0, -1 }) do
                local ran = false
                local err = error_of(function ()
                    async.with_timeout(ms, function () ran = true end)
                end)
                assert.is_equal("Timeout", err.kind)
                assert.is_equal("Timed out immediately", err.message)
                assert.is_false(ran)
            end
        end)
    end)

    describe("finally and on_cancel", function ()
        it("finally runs cleanup on success, failure and cancellation", function ()
            local log = {}
            async.finally(function () end, function () table.insert(log, "ok") end)
            pcall(async.finally, function () error("x") end, function () table.insert(log, "err") end)
            async.scope(function ()
                local job = async.launch(function ()
                    async.finally(function () async.delay(1000) end, function ()
                        async.delay(5) -- cleanup may suspend: it is not cancellable
                        table.insert(log, "cancelled")
                    end)
                end)
                async.delay(5)
                job:cancel()
            end)
            assert.are.same({ "ok", "err", "cancelled" }, log)
        end)

        it("finally returns the body's values", function ()
            assert.is_equal(7, async.finally(function () return 7 end, function () end))
        end)

        it("on_cancel handlers run LIFO when the scope is cancelled", function ()
            local log = {}
            async.scope(function ()
                local job = async.launch(function (scope)
                    scope:on_cancel(function () table.insert(log, 1) end)
                    scope:on_cancel(function ()
                        async.delay(1)
                        table.insert(log, 2)
                    end)
                    async.delay(1000)
                end)
                async.delay(5)
                job:cancel()
            end)
            assert.are.same({ 2, 1 }, log)
        end)

        it("on_cancel handlers do not run on success", function ()
            local ran = false
            async.scope(function (scope)
                scope:on_cancel(function () ran = true end)
            end)
            assert.is_false(ran)
        end)
    end)

    describe("Deferred", function ()
        it("await on a cancelled job raises JobCancelled", function ()
            async.scope(function ()
                local deferred = async.async(function () async.delay(1000) end)
                deferred:cancel()
                assert.is_equal("JobCancelled", error_of(function () async.await(deferred) end).kind)
            end)
        end)
    end)

    describe("completable deferred", function ()
        it("complete returns value", function ()
            local d = async.completable_deferred()
            assert.is_true(d:complete(42))
            assert.is_equal(42, async.await(d))
        end)

        it("complete_exceptionally raises", function ()
            local d = async.completable_deferred()
            assert.is_true(d:complete_exceptionally({ kind = "Bad", message = "bad" }))
            local ok, err = async.try_await(d)
            assert.is_false(ok)
            assert.is_equal("Bad", err.kind)
        end)

        it("cancel completes cancelled", function ()
            local d = async.completable_deferred()
            assert.is_true(d:cancel())
            async.join(d)
            assert.is_true(d:is_cancelled())
            assert.is_true(d:is_completed())
            local ok, err = async.try_await(d)
            assert.is_false(ok)
            assert.is_equal("JobCancelled", err.kind)
        end)

        it("complete returns false second time", function ()
            local d = async.completable_deferred()
            assert.is_true(d:complete(1))
            assert.is_false(d:complete(2))
        end)
    end)

    describe("channel", function ()
        it("delivers buffered values in order and ends iteration on close", function ()
            local ch = async.channel(4)
            for i = 1, 3 do
                ch:send(i)
            end
            ch:close()
            local got = {}
            for v in ch:iter() do
                table.insert(got, v)
            end
            assert.are.same({ 1, 2, 3 }, got)
            assert.is_true(ch:is_closed())
        end)

        it("rendezvous send waits for a receiver", function ()
            local log = {}
            async.scope(function ()
                local ch = async.channel()
                async.launch(function ()
                    ch:send("x")
                    table.insert(log, "sent")
                end)
                async.delay(10)
                table.insert(log, "receiving")
                table.insert(log, ch:receive())
            end)
            assert.are.same({ "receiving", "x", "sent" }, log)
        end)

        it("streams between jobs", function ()
            local sum = 0
            async.scope(function ()
                ---@type luastd.async.Channel<integer>
                local ch = async.channel(1)
                async.launch(function ()
                    for i = 1, 10 do
                        ch:send(i)
                    end
                    ch:close()
                end)
                for v in ch:iter() do
                    sum = sum + v
                end
            end)
            assert.is_equal(55, sum)
        end)

        it("raises ChannelClosed and rejects nil", function ()
            local ch = async.channel(1)
            ch:close()
            assert.is_equal("ChannelClosed", error_of(function () ch:receive() end).kind)
            assert.is_equal("ChannelClosed", error_of(function () ch:send(1) end).kind)
            ---@diagnostic disable-next-line: param-type-mismatch
            assert.is_equal("InvalidArgument", error_of(function () async.channel(1):send(nil) end).kind)
        end)

        it("try_send takes room or reports the channel state", function ()
            local ch = async.channel(1)
            assert.is_true(ch:try_send(1))
            local ok, err = ch:try_send(2)
            assert.is_false(ok)
            assert.is_equal("ChannelFull", err.kind)
            assert.is_equal(1, ch:receive())
            assert.is_true(ch:try_send(3))
            ch:close()
            local closed_ok, closed_err = ch:try_send(4)
            assert.is_false(closed_ok)
            assert.is_equal("ChannelClosed", closed_err.kind)
        end)

        it("try_send on a rendezvous channel requires a waiting receiver", function ()
            local ch = async.channel()
            local ok, err = ch:try_send(1)
            assert.is_false(ok)
            assert.is_equal("ChannelFull", err.kind)
            local received
            async.launch(function () received = ch:receive() end)
            async.yield()
            assert.is_true(ch:try_send(2))
            async.yield()
            assert.is_equal(2, received)
        end)

        it("try_receive reports values, empty, and closed states", function ()
            local ch = async.channel(1)
            local ok, _, err = ch:try_receive()
            assert.is_false(ok)
            assert.is_equal("ChannelEmpty", err.kind)
            assert.is_true(ch:try_send(1))
            ok, err = ch:try_receive()
            assert.is_true(ok)
            assert.is_equal(1, err)
            ch:close()
            ok, _, err = ch:try_receive()
            assert.is_false(ok)
            assert.is_equal("ChannelClosed", err.kind)
        end)

        it("drop_oldest removes the oldest buffered value", function ()
            local ch = async.channel(2, "drop_oldest")
            assert.is_true(ch:try_send(1))
            assert.is_true(ch:try_send(2))
            assert.is_true(ch:try_send(3))
            assert.is_equal(2, ch:receive())
            assert.is_equal(3, ch:receive())
        end)

        it("drop_latest keeps the oldest buffered value", function ()
            local ch = async.channel(2, "drop_latest")
            assert.is_true(ch:try_send(1))
            assert.is_true(ch:try_send(2))
            assert.is_true(ch:try_send(3))
            assert.is_equal(1, ch:receive())
            assert.is_equal(2, ch:receive())
        end)

        it("conflated channels keep only the latest value", function ()
            local ch = async.channel(async.CONFLATED)
            assert.is_true(ch:try_send(1))
            assert.is_true(ch:try_send(2))
            assert.is_true(ch:try_send(3))
            assert.is_equal(3, ch:receive())
        end)

        it("a close cause is raised once the buffer is drained", function ()
            local ch = async.channel(2)
            ch:send(1)
            ch:send(2)
            local cause = luastd_test.TestException("boom")
            ch:close(cause)
            assert.is_equal(1, ch:receive())
            assert.is_equal(2, ch:receive())
            local err = error_of(function () ch:receive() end)
            assert.is_true(cause == err)
        end)

        it("the first close cause is retained", function ()
            local ch = async.channel(1)
            local cause = luastd_test.TestException("first")
            ch:close(cause)
            ch:close(luastd_test.TestException("second"))
            ch:close()
            local err = error_of(function () ch:receive() end)
            assert.is_true(cause == err)
        end)

        it("iteration raises the close cause after the buffered values", function ()
            local ch = async.channel(1)
            ch:send(1)
            local cause = luastd_test.TestException("closed")
            ch:close(cause)
            local got = {}
            local err = error_of(function ()
                for v in ch:iter() do
                    table.insert(got, v)
                end
            end)
            assert.are.same({ 1 }, got)
            assert.is_true(cause == err)
        end)

        it("receive is a cancellation point", function ()
            async.scope(function ()
                local ch = async.channel()
                local job = async.launch(function () ch:receive() end)
                async.delay(5)
                job:cancel()
                async.join(job)
                assert.is_true(job:is_cancelled())
            end)
        end)

        it("debounce emits the last value after quiet and flushes on close", function ()
            local got = {}
            async.scope(function ()
                local ch = async.channel(8)
                local quiet = ch:debounce(20)
                async.launch(function ()
                    ch:send(1)
                    ch:send(2)
                    async.delay(50)
                    ch:send(3)
                    ch:send(4)
                    ch:close()
                end)
                for v in quiet:iter() do
                    table.insert(got, v)
                end
            end)
            assert.are.same({ 2, 4 }, got)
        end)
    end)

    describe("channel cancellation", function ()
        it("cancel stops a blocked sender quietly", function ()
            local sent_after = false
            local job
            async.scope(function ()
                local ch = async.channel()
                job = async.launch(function ()
                    ch:send(1) -- waits for a receiver that never comes
                    sent_after = true
                end)
                async.delay(5)
                ch:cancel()
            end) -- no error reaches the scope
            assert.is_false(sent_after)
            assert.is_true(job:is_cancelled())
        end)

        it("later sends on a cancelled channel cancel the sender", function ()
            local job
            async.scope(function ()
                local ch = async.channel(4)
                ch:cancel()
                job = async.launch(function () ch:send(1) end)
            end)
            assert.is_true(job:is_cancelled())
        end)

        it("cancel drops buffered values and ends iteration", function ()
            local ch = async.channel(4)
            ch:send(1)
            ch:send(2)
            ch:cancel()
            assert.is_true(ch:is_closed())
            local got = {}
            for v in ch:iter() do
                table.insert(got, v)
            end
            assert.are.same({}, got)
        end)
    end)

    describe("produce", function ()
        it("closes the channel when the producer ends", function ()
            local got = {}
            async.scope(function ()
                local ch = async.produce(function (out)
                    for i = 1, 3 do
                        out:send(i)
                    end
                end)
                for v in ch:iter() do
                    table.insert(got, v)
                end
            end)
            assert.are.same({ 1, 2, 3 }, got)
        end)

        it("passes the producer's scope and honours the capacity", function ()
            local sent = 0
            async.scope(function ()
                local ch = async.produce(function (out, scope)
                    assert.is_true(scope:is_active())
                    for i = 1, 3 do
                        out:send(i)
                        sent = i
                    end
                end, 2)
                async.delay(10)
                assert.is_equal(2, sent) -- third send waits for room
                ch:cancel()
            end)
        end)

        it("is cancelled when the consumer cancels", function ()
            local cleaned = false
            async.scope(function ()
                local ch = async.produce(function (out)
                    async.finally(function ()
                        local i = 0
                        while true do
                            i = i + 1
                            out:send(i)
                        end
                    end, function () cleaned = true end)
                end)
                assert.is_equal(1, ch:receive())
                ch:cancel()
            end)
            assert.is_true(cleaned)
        end)

        it("a failing producer fails the scope", function ()
            local err = error_of(function ()
                async.scope(function ()
                    local ch = async.produce(function (out)
                        out:send(1)
                        error({ kind = "ProducerFailed" })
                    end)
                    for _ in ch:iter() do end
                end)
            end)
            assert.is_equal("ProducerFailed", err.kind)
        end)
    end)

    describe("each", function ()
        local function endless()
            return async.produce(function (out)
                local i = 0
                while true do
                    i = i + 1
                    out:send(i)
                end
            end)
        end

        it("stops when fn returns false and cancels the producer (no hang)", function ()
            local got = {}
            -- A regression would hang the scope on the endless producer; the
            -- timeout turns that into a failure.
            async.with_timeout(1000, function ()
                async.scope(function ()
                    endless():each(function (v)
                        table.insert(got, v)
                        return v < 3
                    end)
                end)
            end)
            assert.are.same({ 1, 2, 3 }, got)
        end)

        it("cancels the channel when fn raises", function ()
            local ch
            local err = error_of(function ()
                async.with_timeout(1000, function ()
                    async.scope(function ()
                        ch = endless()
                        ch:each(function () error({ kind = "Stop" }) end)
                    end)
                end)
            end)
            assert.is_equal("Stop", err.kind)
            assert.is_true(ch:is_closed())
        end)

        it("cancels the channel when the consumer is cancelled", function ()
            local ch
            async.with_timeout(1000, function ()
                async.scope(function ()
                    ch = endless()
                    local consumer = async.launch(function ()
                        ch:each(function () async.delay(1) end)
                    end)
                    async.delay(10)
                    consumer:cancel()
                end)
            end)
            assert.is_true(ch:is_closed())
        end)

        it("runs to the end of a closed channel", function ()
            local ch, got = async.channel(3), {}
            for i = 1, 3 do
                ch:send(i)
            end
            ch:close()
            ch:each(function (v) table.insert(got, v) end)
            assert.are.same({ 1, 2, 3 }, got)
        end)

        it("iter with an early break needs cancel to release the producer", function ()
            async.with_timeout(1000, function ()
                async.scope(function ()
                    local ch = endless()
                    for v in ch:iter() do
                        if v == 2 then break end
                    end
                    ch:cancel() -- without this the scope would wait forever
                end)
            end)
        end)
    end)

    describe("debounce and throttle", function ()
        it("debounce runs only the last call", function ()
            local calls = {}
            async.scope(function ()
                local save = async.debounce(20, function (v) table.insert(calls, v) end)
                save(1)
                save(2)
                async.delay(5)
                save(3)
            end)
            assert.are.same({ 3 }, calls)
        end)

        it("throttle runs the leading call per window", function ()
            local calls = {}
            local hit = async.throttle(30, function (v) table.insert(calls, v) end)
            hit(1)
            hit(2)
            async.delay(40)
            hit(3)
            hit(4)
            assert.are.same({ 1, 3 }, calls)
        end)
    end)

    describe("context", function ()
        it("is_active is true outside cancellation", function ()
            assert.is_true(async.is_active())
        end)

        it("rejects bad arguments", function ()
            ---@diagnostic disable-next-line: param-type-mismatch
            assert.is_equal("InvalidArgument", error_of(function () async.launch(42) end).kind)
            assert.is_equal("InvalidArgument", error_of(function () async.delay(-1) end).kind)
            assert.is_equal(
                "InvalidArgument",
                ---@diagnostic disable-next-line: param-type-mismatch
                error_of(function () async.with_timeout("1", function () end) end).kind
            )
        end)
    end)

    describe("mutex and semaphore", function ()
        it("mutex serializes", function ()
            async.scope(function ()
                local m = async.mutex()
                local order = {}
                local function worker(label)
                    m:with_lock(function ()
                        table.insert(order, label .. "a")
                        async.yield()
                        table.insert(order, label .. "b")
                    end)
                end
                async.launch(function () worker("X") end)
                async.launch(function () worker("Y") end)
                async.delay(50)
                -- each critical section runs to completion before the next
                assert.is_true(#order == 4)
            end)
        end)

        it("semaphore limits concurrency", function ()
            async.scope(function ()
                local sem = async.semaphore(2)
                local running = 0
                local maxrunning = 0
                local function worker()
                    sem:with_permit(function ()
                        running = running + 1
                        if running > maxrunning then maxrunning = running end
                        async.delay(10)
                        running = running - 1
                    end)
                end
                for i = 1, 5 do
                    async.launch(worker)
                end
                async.delay(100)
                assert.is_true(maxrunning <= 2)
            end)
        end)

        it("try_acquire", function ()
            async.scope(function ()
                local sem = async.semaphore(1)
                assert.is_true(sem:try_acquire())
                assert.is_false(sem:try_acquire())
                sem:release()
                assert.is_true(sem:try_acquire())
            end)
        end)
    end)

    describe("mutex and semaphore", function ()
        it("mutex serializes", function ()
            local counter = 0
            async.scope(function ()
                local m = async.mutex()
                local jobs = {}
                for i = 1, 5 do
                    table.insert(
                        jobs,
                        async.launch(function ()
                            m:with_lock(function ()
                                local v = counter
                                async.delay(1)
                                counter = v + 1
                            end)
                        end)
                    )
                end
                for _, j in ipairs(jobs) do
                    async.join(j)
                end
            end)
            assert.is_equal(5, counter)
        end)

        it("semaphore limits concurrency", function ()
            local max_seen, current = 0, 0
            async.scope(function ()
                local sem = async.semaphore(2)
                local jobs = {}
                for i = 1, 6 do
                    table.insert(
                        jobs,
                        async.launch(function ()
                            sem:with_permit(function ()
                                current = current + 1
                                if current > max_seen then max_seen = current end
                                async.delay(5)
                                current = current - 1
                            end)
                        end)
                    )
                end
                for _, j in ipairs(jobs) do
                    async.join(j)
                end
            end)
            assert.is_true(max_seen <= 2)
        end)

        it("try_acquire and available_permits", function ()
            local sem = async.semaphore(2)
            assert.is_true(sem:try_acquire())
            assert.is_equal(1, sem:available_permits())
            assert.is_true(sem:try_acquire())
            assert.is_equal(0, sem:available_permits())
            assert.is_false(sem:try_acquire())
            sem:release()
            assert.is_equal(1, sem:available_permits())
        end)

        it("mutex is not a semaphore", function ()
            assert.is_nil(getmetatable(async.mutex())._core)
        end)

        it("semaphore fairness", function ()
            local log = {}
            async.scope(function ()
                local sem = async.semaphore(1)
                sem:acquire()
                async.launch(function ()
                    async.delay(0)
                    table.insert(log, "first-acquire-wait")
                    sem:acquire()
                    table.insert(log, "first-got")
                end)
                async.launch(function ()
                    async.delay(0)
                    table.insert(log, "second-acquire-wait")
                    sem:acquire()
                    table.insert(log, "second-got")
                end)
                async.delay(5)
                table.insert(log, "release1")
                sem:release()
                async.delay(5)
                table.insert(log, "release2")
                sem:release()
                async.delay(5)
            end)
            -- first waiter should get permit before second
            local i1, i2 = 0, 0
            for i, v in ipairs(log) do
                if v == "first-got" then i1 = i end
                if v == "second-got" then i2 = i end
            end
            assert.is_true(i1 > 0 and i2 > 0 and i1 < i2)
        end)

        it("semaphore cancellation returns permit back", function ()
            local sem = async.semaphore(1)
            sem:acquire()
            assert.is_equal(0, sem:available_permits())
            local job
            async.scope(function ()
                job = async.launch(function ()
                    assert.is_false(sem:try_acquire())
                    sem:acquire()
                end)
                async.delay(5)
                job:cancel()
            end)
            assert.is_equal(0, sem:available_permits())
            sem:release()
            assert.is_equal(1, sem:available_permits())
        end)

        it("semaphore cancellation does not resume waiters", function ()
            local log = {}
            async.scope(function ()
                local sem = async.semaphore(1)
                sem:acquire()
                local job1 = async.launch(function ()
                    table.insert(log, "job1-wait")
                    sem:acquire()
                    table.insert(log, "job1-got")
                end)
                local job2 = async.launch(function ()
                    table.insert(log, "job2-wait")
                    sem:acquire()
                    table.insert(log, "job2-got")
                end)
                async.delay(5)
                table.insert(log, "cancel-job2")
                job2:cancel()
                async.delay(5)
                table.insert(log, "cancel-job1")
                job1:cancel()
                async.delay(5)
            end)
            -- neither should have got
            local got = false
            for _, v in ipairs(log) do
                if v:match("got") then got = true end
            end
            assert.is_false(got)
        end)

        it("mutex tryLock and isLocked", function ()
            local m = async.mutex()
            assert.is_false(m:is_locked())
            assert.is_true(m:try_lock())
            assert.is_true(m:is_locked())
            assert.is_false(m:try_lock())
            m:unlock()
            assert.is_false(m:is_locked())
        end)

        it("mutex withLock failure unlocks", function ()
            local m = async.mutex()
            local ok, err = pcall(function ()
                m:with_lock(function ()
                    assert.is_true(m:is_locked())
                    error({ kind = "TestException" })
                end)
            end)
            assert.is_false(ok)
            assert.is_false(m:is_locked())
        end)

        it("mutex holdsLock", function ()
            local m = async.mutex()
            local o1 = {}
            local o2 = {}
            m:lock(o1)
            assert.is_true(m:holds_lock(o1))
            assert.is_false(m:holds_lock(o2))
            m:unlock(o1)
            assert.is_false(m:holds_lock(o1))
        end)

        it("mutex unlock wrong owner throws", function ()
            local m = async.mutex()
            local o1 = {}
            local o2 = {}
            m:lock(o1)
            local ok, err = pcall(function () m:unlock(o2) end)
            assert.is_false(ok)
            assert.is_equal("IllegalState", err.kind)
            m:unlock(o1)
        end)

        it("semaphore acquiredPermits", function ()
            local sem = async.semaphore(5, 4)
            assert.is_equal(1, sem:available_permits())
            sem:acquire()
            assert.is_equal(0, sem:available_permits())
            assert.is_false(sem:try_acquire())
            sem:release()
            assert.is_equal(1, sem:available_permits())
            assert.is_true(sem:try_acquire())
        end)

        it("semaphore release too many throws", function ()
            local sem = async.semaphore(5, 4)
            for i = 1, 4 do
                sem:release()
            end
            assert.is_equal(5, sem:available_permits())
            local ok, err = pcall(function () sem:release() end)
            assert.is_false(ok)
        end)

        it("mutex initial locked", function ()
            local m = async.mutex(true)
            assert.is_true(m:is_locked())
            m:unlock()
            assert.is_false(m:is_locked())
        end)
    end)

    describe("lazy jobs", function ()
        it("async_lazy auto starts on await", function ()
            async.scope(function ()
                local d = async.async_lazy(function () return 7 end)
                assert.is_false(d:is_active())
                assert.is_false(d:is_completed())
                assert.is_equal(7, async.await(d))
                assert.is_equal(7, async.await(d))
            end)
        end)

        it("launch_lazy cancel before start", function ()
            async.scope(function ()
                local job = async.launch_lazy(function () end)
                assert.is_false(job:is_active())
                job:cancel()
                assert.is_true(job:is_cancelled())
                assert.is_true(job:is_completed())
                assert.is_false(job:start())
            end)
        end)

        it("job:start method schedules lazy", function ()
            local ran = false
            async.scope(function ()
                local job = async.launch_lazy(function ()
                    ran = true
                end)
                assert.is_false(ran)
                job:start()
                async.join(job)
                assert.is_true(ran)
            end)
        end)
    end)
end)
