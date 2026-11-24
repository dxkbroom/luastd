-- kotlin: kotlinx-coroutines-core/common/test/channels/BroadcastTest.kt@1.11.0
describe("BroadcastTest", function ()
    -- not-applicable: Kotlin BroadcastChannel and its broadcast/subscribe
    -- operations are deprecated and luastd exposes Channel and SharedFlow.
    pending("testBroadcastBasic")

    -- not-applicable: Channel does not expose the deprecated broadcast view.
    pending("testChannelBroadcastLazyCancel")

    -- not-applicable: Channel does not expose the deprecated broadcast view.
    pending("testChannelBroadcastLazyClose")

    -- not-applicable: Channel does not expose the deprecated broadcast view.
    pending("testChannelBroadcastEagerCancel")

    -- not-applicable: Channel does not expose the deprecated broadcast view.
    pending("testChannelBroadcastEagerClose")

    -- not-applicable: luastd has no broadcast channel to close with an error.
    pending("testBroadcastCloseWithException")
end)
