-- Port of kotlinx.coroutines' FlatMapLatestTest.
-- flatMapLatest switches on new upstream; cancellation semantics differ.
-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/FlatMapLatestTest.kt@1.11.0
describe("FlatMapLatestTest", function ()
    -- defer: switching/cancellation semantics not fully ported.
    pending("testFlatMapLatest")
    pending("testEmission")
    pending("testSwitchIntuitiveBehaviour")
    pending("testSwitchRendevouzBuffer")
    pending("testHangFlows")
    pending("testEmptyFlow")
    pending("testFailureInTransform")
    pending("testFailureDownstream")
    pending("testFailureUpstream")
    pending("testTake")
end)
