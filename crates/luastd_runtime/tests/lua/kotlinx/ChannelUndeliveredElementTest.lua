-- kotlin: kotlinx-coroutines-core/common/test/channels/ChannelUndeliveredElementTest.kt@1.11.0
local async = require("luastd.async")
local luastd_test = require("luastd_test")

describe("ChannelUndeliveredElementTest", function ()
    -- adapted: luastd has no onUndeliveredElement callback; verify that a
    -- resource sent and received normally remains available to its consumer.
    it(
        "testSendSuccessfully",
        luastd_test.runtest(function ()
            local channel = async.channel(1)
            local resource = { value = "OK", cancelled = false }
            local sender = async.launch(function () channel:send(resource) end)
            local received = channel:receive()
            assert.is_true(rawequal(resource, received))
            assert.is_equal("OK", received.value)
            assert.is_false(received.cancelled)
            channel:close()
            async.join(sender)
            assert.is_false(resource.cancelled)
        end)
    )

    -- not-applicable: there is no callback API to report a rendezvous send
    -- value cancelled while waiting.
    pending("testRendezvousSendCancelled")

    -- not-applicable: there is no callback API to report a buffered send
    -- value cancelled while waiting for capacity.
    pending("testBufferedSendCancelled")

    -- not-applicable: channel cancellation does not report buffered values
    -- through an onUndeliveredElement callback.
    pending("testUnlimitedChannelCancelled")

    -- not-applicable: conflation drops an older value, but no callback is
    -- exposed to observe its resource cleanup.
    pending("testConflatedResourceCancelled")

    -- not-applicable: a send rejected by close has no undelivered callback
    -- hook through which this test's resource cancellation can be asserted.
    pending("testSendToClosedChannel")

    -- adapted: with no undelivered-element callback API, verify that a
    -- waiting receiver gets the value exactly once and the channel leaves it.
    it(
        "testHandlerIsNotInvoked",
        luastd_test.runtest(function (t)
            local channel = async.channel()
            local receiver = async.launch(function ()
                t:expect(2)
                assert.is_equal("value", channel:receive())
            end)
            t:expect(1)
            channel:send("value")
            async.join(receiver)
            t:finish(3)
        end)
    )

    -- not-applicable: overflow strategies drop values, but there is no
    -- callback hook to observe which values were discarded.
    pending("testChannelBufferOverflow")

    -- not-applicable: there is no callback hook whose non-invocation can be
    -- asserted after a conflated channel closes.
    pending("testTrySendDoesNotInvokeHandlerOnClosedConflatedChannel")

    -- not-applicable: there is no callback hook whose non-invocation can be
    -- asserted after a buffered channel closes.
    pending("testTrySendDoesNotInvokeHandlerOnClosedChannel")

    -- not-applicable: DROP_LATEST plus onUndeliveredElement is not expressible
    -- because async.channel does not accept an undelivered-element callback.
    pending("testTrySendDoesNotInvokeHandler")
end)
