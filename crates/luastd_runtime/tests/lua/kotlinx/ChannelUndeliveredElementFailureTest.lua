-- kotlin: kotlinx-coroutines-core/common/test/channels/ChannelUndeliveredElementFailureTest.kt@1.11.0
describe("ChannelUndeliveredElementFailureTest", function ()
    -- not-applicable: Channel has no onUndeliveredElement callback or atomic
    -- start mode to deliver callback failures when a queued send is cancelled.
    pending("testSendCancelledFail")

    -- not-applicable: Channel has no onUndeliveredElement callback, and Lua
    -- has no select/onSend clause or undispatched launch mode.
    pending("testSendSelectCancelledFail")

    -- not-applicable: Channel has no onUndeliveredElement callback to report
    -- a buffered value lost when its waiting receiver is cancelled.
    pending("testReceiveCancelledFail")

    -- not-applicable: Channel has no onUndeliveredElement callback or
    -- select/onReceive clause for the cancelled receive operation.
    pending("testReceiveSelectCancelledFail")

    -- not-applicable: Channel has no onUndeliveredElement callback or
    -- receiveCatching operation to report a value lost on cancellation.
    pending("testReceiveCatchingCancelledFail")

    -- not-applicable: Channel has no onUndeliveredElement callback or
    -- select/onReceiveCatching clause for the cancelled receive operation.
    pending("testReceiveOrClosedSelectCancelledFail")

    -- not-applicable: Channel iteration has no onUndeliveredElement callback
    -- to report a value consumed by a cancelled iterator operation.
    pending("testHasNextCancelledFail")

    -- not-applicable: Channel:cancel drops buffered values without an
    -- onUndeliveredElement callback or callback-failure result.
    pending("testChannelCancelledFail")

    -- not-applicable: channel close cannot invoke a user callback when a
    -- later send is rejected; luastd has no onUndeliveredElement option.
    pending("testFailedHandlerInClosedConflatedChannel")

    -- not-applicable: channel close cannot invoke a user callback when a
    -- later send is rejected; luastd has no onUndeliveredElement option.
    pending("testFailedHandlerInClosedBufferedChannel")

    -- not-applicable: overflow modes do not accept an undelivered-element
    -- callback in luastd, so dropping an old value cannot report its failure.
    pending("testSendDropOldestInvokeHandlerBuffered")

    -- not-applicable: overflow modes do not accept an undelivered-element
    -- callback in luastd, so dropping a new value cannot report its failure.
    pending("testSendDropLatestInvokeHandlerBuffered")

    -- not-applicable: conflated channels do not accept an undelivered-element
    -- callback in luastd, so replacing the buffered value cannot report failure.
    pending("testSendDropOldestInvokeHandlerConflated")
end)
