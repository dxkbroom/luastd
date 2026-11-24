-- Port of kotlinx.coroutines' SafeFlowTest.
-- State-machine context invariants are not-applicable (no dispatchers).
-- kotlin: kotlinx-coroutines-core/common/test/flow/SafeFlowTest.kt@1.11.0
describe("SafeFlowTest", function ()
    -- not-applicable: dispatcher/state-machine invariants in a single-threaded runtime.
    pending("testEmissionsFromDifferentStateMachine")
end)
