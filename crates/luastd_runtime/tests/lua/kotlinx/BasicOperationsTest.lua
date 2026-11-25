-- Port of kotlinx.coroutines' BasicOperationsTest.
-- luastd channels have send/receive/try_send/close/cancel/iter/each;
-- receive_catching, invoke_on_close and an iterator protocol are not available.

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/channels/BasicOperationsTest.kt@1.11.0
describe("BasicOperationsTest", function ()
    it(
        "testSimpleSendReceive",
        runtest(function ()
            -- adapted: no TestChannelKind matrix; rendezvous and buffered
            -- channels send every value in order and then close.
            for _, cap in ipairs({ 0, 1, 20 }) do
                local channel = async.channel(cap)
                async.launch(function ()
                    for i = 0, 19 do
                        channel:send(i)
                    end
                    channel:close()
                end)
                local expected = 0
                for x in channel:iter() do
                    assert.is_equal(expected, x)
                    expected = expected + 1
                end
                assert.is_equal(20, expected)
            end
        end)
    )

    it(
        "testTrySendToFullChannel",
        runtest(function ()
            local channel = async.channel(1)
            assert.is_true(channel:try_send(1))
            local ok, err = channel:try_send(2)
            assert.is_false(ok)
            assert.is_equal("ChannelFull", err.kind)
        end)
    )

    it(
        "testTrySendAfterClose",
        runtest(function ()
            local channel = async.channel()
            channel:close()
            local ok, err = channel:try_send(1)
            assert.is_false(ok)
            assert.is_equal("ChannelClosed", err.kind)
        end)
    )

    it(
        "testSendAfterClose",
        runtest({ expected = "ChannelClosed" }, function ()
            local channel = async.channel()
            channel:close()
            async.launch(function ()
                channel:send(1)
            end)
        end)
    )

    -- adapted: no receive_catching/ChannelResult API or TestChannelKind matrix;
    -- compare receive and try_receive success/closed behavior instead.
    it(
        "testReceiveCatching",
        runtest(function (t)
            local channel = async.channel()
            async.launch(function ()
                t:expect(2)
                channel:send(1)
            end)
            t:expect(1)
            assert.is_equal(1, channel:receive())
            t:expect(3)
            async.launch(function ()
                t:expect(4)
                channel:close()
            end)
            local ok, err = pcall(function () channel:receive() end)
            assert.is_false(ok)
            assert.is_equal("ChannelClosed", err.kind)
            t:expect(5)
            local received, _, try_err = channel:try_receive()
            assert.is_false(received)
            assert.is_equal("ChannelClosed", try_err.kind)
            t:finish(6)
        end)
    )

    -- defer: no `invoke_on_close`.
    pending("testInvokeOnClose")
    pending("testInvokeOnClosed")
    pending("testMultipleInvokeOnClose")

    -- defer: `iter` is a plain closure, with no `has_next`/`next` protocol.
    pending("testIteratorHasNextMustPrecedeNext")

    -- defer: no `invoke_on_close`.
    pending("testCancelledChannelInvokeOnClose")
    pending("testCancelledChannelWithCauseInvokeOnClose")
    pending("testThrowingInvokeOnClose")
end)
