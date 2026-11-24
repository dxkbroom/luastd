-- kotlin: kotlinx-coroutines-core/common/test/flow/channels/ChannelBuildersFlowTest.kt@1.11.0
describe("ChannelBuildersFlowTest", function ()
    -- not-applicable: luastd has no Channel:consume_as_flow bridge.
    pending("testChannelConsumeAsFlow")

    -- not-applicable: luastd has no Channel:receive_as_flow bridge.
    pending("testChannelReceiveAsFlow")

    -- not-applicable: this tests consume_as_flow cancellation semantics, and
    -- luastd does not expose that channel-to-flow operator.
    pending("testConsumeAsFlowCancellation")

    -- not-applicable: this tests receive_as_flow cancellation semantics, and
    -- luastd does not expose that channel-to-flow operator.
    pending("testReceiveAsFlowCancellation")

    -- not-applicable: this tests consume_as_flow error semantics, and luastd
    -- does not expose that channel-to-flow operator.
    pending("testConsumeAsFlowException")

    -- not-applicable: this tests receive_as_flow error semantics, and luastd
    -- does not expose that channel-to-flow operator.
    pending("testReceiveAsFlowException")

    -- not-applicable: Flow has no produce_in operator or channel identity to
    -- assert for fused consume_as_flow.
    pending("testConsumeAsFlowProduceFusing")

    -- not-applicable: Flow has no produce_in operator or channel identity to
    -- assert for fused receive_as_flow.
    pending("testReceiveAsFlowProduceFusing")

    -- not-applicable: Flow has no produce_in operator returning a buffered
    -- channel for this test to inspect.
    pending("testConsumeAsFlowProduceBuffered")

    -- not-applicable: Flow has no produce_in operator or atomic coroutine
    -- start mode used by this test.
    pending("testProduceInAtomicity")
end)
