-- Port of kotlinx.coroutines' TransformLatestTest.
-- transformLatest switches on new upstream; cancellation semantics differ.
-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/TransformLatestTest.kt@1.11.0
describe("TransformLatestTest", function ()
    -- defer: switching/cancellation semantics not fully ported.
    pending("testEmission")
    pending("testEmptyFlow")
    pending("testFailureDownstream")
    pending("testFailureInTransform")
    pending("testFailureUpstream")
    pending("testHangFlows")
    pending("testIsolatedContext")
    pending("testSwitchBuffer")
    pending("testSwitchIntuitiveBehaviour")
    pending("testSwitchRendezvousBuffer")
    pending("testTake")
    pending("testTransformLatest")
end)
