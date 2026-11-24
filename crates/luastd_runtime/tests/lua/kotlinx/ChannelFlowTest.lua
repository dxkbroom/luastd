-- kotlin: kotlinx-coroutines-core/common/test/flow/channels/ChannelFlowTest.kt@1.11.0
describe("ChannelFlowTest", function ()
    -- not-applicable: there is no channelFlow builder or synchronous
    -- try_send operation in luastd.
    pending("testRegular")

    -- not-applicable: Flow:buffer cannot test channelFlow's bounded send
    -- capacity because the channelFlow builder is absent.
    pending("testBuffer")

    -- not-applicable: there is no channelFlow builder or Channel.CONFLATED
    -- send channel to exercise conflation while producing.
    pending("testConflated")

    -- not-applicable: channelFlow's producer channel and invokeOnClose
    -- lifecycle callback are not exposed.
    pending("testFailureCancelsChannel")

    -- not-applicable: channelFlow's producer channel and its structured
    -- producer/consumer cancellation relationship are not exposed.
    pending("testFailureInSourceCancelsConsumer")

    -- not-applicable: channelFlow's producer scope is absent; luastd has no
    -- CoroutineStart.ATOMIC child start used by this case.
    pending("testScopedCancellation")

    -- not-applicable: this test depends on the private mergeOneCoroutine
    -- channelFlow builder pattern, which luastd does not expose.
    pending("testMergeOneCoroutineWithCancellation")

    -- not-applicable: this test depends on the private mergeTwoCoroutines
    -- channelFlow builder pattern, which luastd does not expose.
    pending("testMergeTwoCoroutinesWithCancellation")

    -- not-applicable: the ignored case uses channelFlow producer children
    -- and hang/withTimeout scheduling, none of which compose in luastd.
    pending("testBufferWithTimeout")

    -- not-applicable: channelFlow's child producer scope and cancelAndJoin
    -- operation are not exposed.
    pending("testChildCancellation")

    -- not-applicable: channelFlow and its awaitClose lifetime are absent.
    pending("testClosedPrematurely")

    -- not-applicable: channelFlow and its awaitClose lifetime are absent.
    pending("testNotClosedPrematurely")

    -- not-applicable: callbackFlow and its producer close/hang behavior
    -- are not exposed.
    pending("testCancelledOnCompletion")
end)
