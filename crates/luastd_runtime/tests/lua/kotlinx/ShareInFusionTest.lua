-- kotlin: kotlinx-coroutines-core/common/test/flow/sharing/ShareInFusionTest.kt@1.11.0
describe("ShareInFusionTest", function ()
    -- defer: luastd has Flow:cancellable/flow_on/buffer, but no share_in
    -- operator that returns the non-mutable SharedFlow under test; the identity
    -- fusion assertions therefore have no equivalent object to inspect.
    pending("testOperatorFusion")

    -- defer: Flow:flow_on and CoroutineName exist, but no share_in(scope,
    -- started) exists to collect the context-tagged upstream and expose the
    -- shared value to first().
    pending("testFlowOnContextFusion")

    -- defer: luastd has no channel_flow or share_in operator; `flow.new` and
    -- async.produce do not model the fused buffer-before-sharing boundary or
    -- the shared subscriber collection checked here.
    pending("testChannelFlowBufferShareIn")
end)
