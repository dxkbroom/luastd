-- Port of kotlinx.coroutines' BasicOperationsTest.
-- luastd channels have send/receive/close/cancel/iter/each; there is no
-- try_send, receive_catching, invoke_on_close or an iterator protocol.
---@diagnostic disable: await-in-sync

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

    -- defer: no `try_send`.
    pending("testTrySendToFullChannel")
    pending("testTrySendAfterClose")

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

    -- defer: no `receive_catching` or `ChannelResult`.
    pending("testReceiveCatching")

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
