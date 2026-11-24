-- Port of kotlinx.coroutines' TransformLatestTest.
-- transformLatest switches on new upstream; cancellation semantics differ.
-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/TransformLatestTest.kt@1.11.0
describe("TransformLatestTest", function ()
    -- defer: switching/cancellation semantics not fully ported.
    pending("testTransformLatest")
    pending("testEmission")
    pending("testSwitchIntuitiveBehaviour")
    pending("testSwitchRendezvousBuffer")
    pending("testSwitchBuffer")
    pending("testHangFlows")
    pending("testEmptyFlow")
    pending("testIsolatedContext")
    pending("testFailureInTransform")
    pending("testFailureDownstream")
    pending("testFailureUpstream")
    pending("testTake")
end)
