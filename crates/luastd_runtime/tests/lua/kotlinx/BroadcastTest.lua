-- kotlin: kotlinx-coroutines-core/common/test/channels/BroadcastTest.kt@1.11.0
describe("BroadcastTest", function ()
    -- deprecated: Kotlin BroadcastChannel and its broadcast/subscribe
    -- operations are deprecated and luastd exposes Channel and SharedFlow.
    pending("testBroadcastBasic")

    -- deprecated: Channel does not expose the deprecated broadcast view.
    pending("testChannelBroadcastLazyCancel")

    -- deprecated: Channel does not expose the deprecated broadcast view.
    pending("testChannelBroadcastLazyClose")

    -- deprecated: Channel does not expose the deprecated broadcast view.
    pending("testChannelBroadcastEagerCancel")

    -- deprecated: Channel does not expose the deprecated broadcast view.
    pending("testChannelBroadcastEagerClose")

    -- deprecated: luastd has no broadcast channel to close with an error.
    pending("testBroadcastCloseWithException")
end)
