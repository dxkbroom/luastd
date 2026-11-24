-- Port of kotlinx.coroutines' RendezvousChannelTest.
-- Cases that rely on ChannelResult, UNDISTPATCHED, or Kotlin's close behavior
-- remain deferred where luastd has no equivalent.
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/channels/RendezvousChannelTest.kt@1.11.0
describe("RendezvousChannelTest", function ()
    -- adapted: scheduler resumption order differs; assert the send/receive
    -- rendezvous contract and values rather than Kotlin's action trace.
    it(
        "testSimple",
        runtest(function ()
            local q = async.channel(async.RENDEZVOUS)
            assert.is_true(q:is_empty())
            local sent = {}
            local received = {}
            local sender = async.launch(function ()
                for i = 1, 2 do
                    q:send(i)
                    sent[i] = true
                end
            end)
            local receiver = async.launch(function ()
                for i = 1, 2 do
                    received[i] = q:receive()
                end
            end)
            async.join(sender)
            async.join(receiver)
            assert.is_true(q:is_empty())
            assert.are.same({ true, true }, sent)
            assert.are.same({ 1, 2 }, received)
        end)
    )

    -- adapted: ChannelClosed replaces ChannelResult's closed/null result.
    it(
        "testClosedReceiveCatching",
        runtest(function (t)
            local q = async.channel()
            assert.is_true(q:is_empty())
            assert.is_false(q:is_closed())
            t:expect(1)
            async.launch(function ()
                t:expect(3)
                assert.is_equal(42, q:receive())
                t:expect(4)
                local ok, err = pcall(function () q:receive() end)
                assert.is_false(ok)
                assert.is_equal("ChannelClosed", err.kind)
                t:expect(6)
            end)
            t:expect(2)
            q:send(42)
            t:expect(5)
            q:close()
            assert.is_true(q:is_closed_for_receive())
            async.yield()
            t:finish(7)
        end)
    )

    -- adapted: try_receive reports its status with a boolean/error tuple.
    it(
        "testClosedExceptions",
        runtest(function (t)
            local q = async.channel()
            t:expect(1)
            local receiver = async.launch(function ()
                t:expect(4)
                local ok, receive_err = pcall(function () q:receive() end)
                assert.is_false(ok)
                assert.is_equal("ChannelClosed", receive_err.kind)
                t:expect(5)
            end)
            t:expect(2)
            q:close()
            t:expect(3)
            async.yield()
            async.join(receiver)
            t:expect(6)
            local ok, send_err = pcall(function () q:send(42) end)
            assert.is_false(ok)
            assert.is_equal("ChannelClosed", send_err.kind)
            t:finish(7)
        end)
    )

    -- adapted: iterator closure has the same stream behavior, but the
    -- scheduler resumes sender and receiver in a different action order.
    it(
        "testTrySendTryReceive",
        runtest(function (t)
            local q = async.channel()
            assert.is_false(q:try_send(1))
            t:expect(1)
            async.launch(function ()
                t:expect(3)
                local ok = q:try_receive()
                assert.is_false(ok)
                t:expect(4)
                assert.is_equal(2, q:receive())
                t:expect(7)
                ok = q:try_receive()
                assert.is_false(ok)
                async.yield()
                t:expect(9)
                local value_ok, value = q:try_receive()
                assert.is_true(value_ok)
                assert.is_equal(3, value)
                t:expect(10)
            end)
            t:expect(2)
            async.yield()
            t:expect(5)
            assert.is_true(q:try_send(2))
            t:expect(6)
            async.yield()
            t:expect(8)
            q:send(3)
            t:finish(11)
        end)
    )

    -- adapted: stream values are preserved; luastd's scheduler interleaving
    -- differs from Kotlin's test dispatcher without the explicit yield.
    it(
        "testIteratorClosed",
        runtest(function (t)
            local q = async.channel()
            t:expect(1)
            async.launch(function ()
                t:expect(3)
                q:close()
                t:expect(4)
            end)
            t:expect(2)
            for _ in q:iter() do
                t:expect_unreached()
            end
            t:finish(5)
        end)
    )

    -- adapted: stream values are preserved; luastd's scheduler interleaving
    -- differs from Kotlin's test dispatcher with this yield placement.
    it(
        "testIteratorOne",
        runtest(function ()
            local q = async.channel()
            async.launch(function ()
                q:send(1)
                q:close()
            end)
            local values = {}
            for x in q:iter() do
                values[#values + 1] = x
            end
            assert.are.same({ 1 }, values)
        end)
    )

    it(
        "testIteratorOneWithYield",
        runtest(function (t)
            local q = async.channel()
            t:expect(1)
            async.launch(function ()
                t:expect(3)
                q:send(1)
                t:expect(6)
                q:close()
                t:expect(7)
            end)
            t:expect(2)
            async.yield()
            t:expect(4)
            for x in q:iter() do
                t:expect(5)
                assert.is_equal(1, x)
            end
            t:finish(8)
        end)
    )

    it(
        "testIteratorTwo",
        runtest(function ()
            local q = async.channel()
            async.launch(function ()
                q:send(1)
                q:send(2)
                q:close()
            end)
            local values = {}
            for x in q:iter() do
                values[#values + 1] = x
            end
            assert.are.same({ 1, 2 }, values)
        end)
    )

    it(
        "testIteratorTwoWithYield",
        runtest(function ()
            local q = async.channel()
            async.launch(function ()
                q:send(1)
                q:send(2)
                q:close()
            end)
            async.yield()
            local values = {}
            for x in q:iter() do
                values[#values + 1] = x
            end
            assert.are.same({ 1, 2 }, values)
        end)
    )

    -- adapted: a closed rendezvous channel reports ChannelClosed after its
    -- queued value is received, instead of returning ChannelResult.closed.
    it(
        "testSuspendSendOnClosedChannel",
        runtest(function (t)
            local q = async.channel(async.RENDEZVOUS)
            t:expect(1)
            local sender = async.launch(function ()
                t:expect(4)
                q:send(42)
                t:expect(11)
            end)
            t:expect(2)
            async.launch(function ()
                t:expect(5)
                q:close()
                t:expect(6)
            end)
            t:expect(3)
            async.yield()
            t:expect(7)
            async.yield()
            t:expect(8)
            assert.is_equal(42, q:receive())
            t:expect(9)
            local ok, err = pcall(function () q:receive() end)
            assert.is_false(ok)
            assert.is_equal("ChannelClosed", err.kind)
            t:expect(10)
            async.yield()
            async.join(sender)
            t:finish(12)
        end)
    )

    it(
        "testProduceBadClass",
        runtest(function (t)
            local bad = setmetatable({}, {})
            local c = async.produce(function (producer)
                t:expect(1)
                producer:send(bad)
            end)
            assert.is_true(bad == c:receive())
            t:finish(2)
        end)
    )

    -- defer: the source requires CoroutineStart.UNDISPATCHED and catches
    -- channel cancellation as CancellationException (ADR 0005).
    pending("testConsumeAll")

    -- defer: Channel.cancel(cause) is not supported.
    pending("testCancelWithCause")

    it(
        "testDropOldest",
        runtest(function ()
            local channel = async.channel(async.RENDEZVOUS, "drop_oldest")
            channel:send(1)
            channel:send(2)
            channel:send(3)
            assert.is_equal(3, channel:receive())
        end)
    )

    it(
        "testDropLatest",
        runtest(function ()
            local channel = async.channel(async.RENDEZVOUS, "drop_latest")
            channel:send(1)
            channel:send(2)
            channel:send(3)
            assert.is_equal(1, channel:receive())
        end)
    )
end)
