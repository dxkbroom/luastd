-- kotlin: kotlinx-coroutines-core/common/test/channels/ConflatedChannelTest.kt@1.11.0
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("ConflatedChannelTest", function ()
    -- adapted: try_receive reports empty as false plus a ChannelEmpty error
    -- rather than ChannelResult.success(null).
    it(
        "testBasicConflationOfferTryReceive",
        runtest(function ()
            local channel = async.channel(async.CONFLATED)
            local ok, _, err = channel:try_receive()
            assert.is_false(ok)
            assert.is_equal("ChannelEmpty", err.kind)
            assert.is_true(channel:try_send(1))
            assert.is_true(channel:try_send(2))
            assert.is_true(channel:try_send(3))
            assert.is_equal(3, channel:receive())
        end)
    )

    -- adapted: channel closure is represented with is_closed_for_receive and
    -- ChannelClosed rather than ChannelResult.
    it(
        "testConflatedSend",
        runtest(function ()
            local channel = async.channel(async.CONFLATED)
            channel:send(1)
            channel:send(2)
            assert.is_equal(2, channel:receive())
        end)
    )

    it(
        "testConflatedClose",
        runtest(function ()
            local channel = async.channel(async.CONFLATED)
            channel:send(1)
            channel:close()
            assert.is_true(channel:is_closed())
            assert.is_false(channel:is_closed_for_receive())
            assert.is_equal(1, channel:receive())
            assert.is_true(channel:is_closed_for_receive())
            local ok, _, err = channel:try_receive()
            assert.is_false(ok)
            assert.is_equal("ChannelClosed", err.kind)
        end)
    )

    -- adapted: explicit yields ensure the single-threaded executor lets an
    -- already-waiting receiver take each direct handoff before later sends.
    it(
        "testConflationSendReceive",
        runtest(function ()
            local channel = async.channel(async.CONFLATED)
            local values = {}
            async.launch(function ()
                values[1] = channel:receive()
                values[2] = channel:receive()
                values[3] = channel:receive()
            end)
            channel:send(1)
            channel:send(2)
            while values[1] == nil do
                async.yield()
            end
            channel:send(3)
            while values[2] == nil do
                async.yield()
            end
            channel:send(4)
            channel:send(5)
            channel:send(6)
            while values[3] == nil do
                async.yield()
            end
            assert.are.same({ 2, 3, 6 }, values)
        end)
    )

    -- defer: receiveCatching must expose cancellation as CancellationException;
    -- luastd cancellation cannot be caught (ADR 0005).
    pending("testConsumeAll")

    -- defer: Channel.cancel(cause) is not supported.
    pending("testCancelWithCause")
end)
