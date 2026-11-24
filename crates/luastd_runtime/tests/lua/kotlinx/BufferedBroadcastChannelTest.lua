-- kotlin: kotlinx-coroutines-core/common/test/channels/BufferedBroadcastChannelTest.kt@1.11.0
describe("BufferedBroadcastChannelTest", function ()
    -- not-applicable: this exercises deprecated BufferedBroadcastChannel
    -- subscription buffering, which luastd does not expose.
    pending("testConcurrentModification")

    -- not-applicable: this exercises deprecated BufferedBroadcastChannel
    -- subscription buffering, which luastd does not expose.
    pending("testBasic")

    -- not-applicable: this exercises deprecated BufferedBroadcastChannel
    -- subscription buffering, which luastd does not expose.
    pending("testSendSuspend")

    -- not-applicable: this exercises deprecated BufferedBroadcastChannel
    -- subscription buffering, which luastd does not expose.
    pending("testConcurrentSendCompletion")

    -- not-applicable: this exercises deprecated BufferedBroadcastChannel
    -- subscription buffering, which luastd does not expose.
    pending("testForgetUnsubscribed")

    -- not-applicable: this exercises deprecated BufferedBroadcastChannel
    -- subscription buffering, which luastd does not expose.
    pending("testReceiveFullAfterClose")

    -- not-applicable: this exercises deprecated BufferedBroadcastChannel
    -- subscription buffering, which luastd does not expose.
    pending("testCloseSubDuringIteration")

    -- not-applicable: this exercises deprecated BufferedBroadcastChannel
    -- subscription buffering, which luastd does not expose.
    pending("testReceiveFromCancelledSub")

    -- not-applicable: this exercises deprecated BufferedBroadcastChannel
    -- subscription buffering, which luastd does not expose.
    pending("testCancelWithCause")

    -- not-applicable: this exercises deprecated BufferedBroadcastChannel
    -- subscription buffering, which luastd does not expose.
    pending("testReceiveNoneAfterCancel")
end)
