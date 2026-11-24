-- Port of kotlinx.coroutines' FlowInvariantsTest.
-- Context/dispatcher invariants are not-applicable (no dispatchers).
-- kotlin: kotlinx-coroutines-core/common/test/flow/FlowInvariantsTest.kt@1.11.0
describe("FlowInvariantsTest", function ()
    -- not-applicable: no dispatcher/context invariants in a single-threaded runtime.
    pending("testWithContextContract")
    pending("testWithDispatcherContractViolated")
    pending("testWithNameContractViolated")
    pending("testWithContextDoesNotChangeExecution")
    pending("testScopedJob")
    pending("testScopedJobWithViolation")
    pending("testMergeViolation")
    pending("testNoMergeViolation")
    pending("testScopedCoroutineNoViolation")
    pending("testEmptyCoroutineContextMap")
    pending("testEmptyCoroutineContextTransform")
    pending("testEmptyCoroutineContextTransformWhile")
    pending("testEmptyCoroutineContextViolationTransform")
    pending("testEmptyCoroutineContextViolationTransformWhile")
end)