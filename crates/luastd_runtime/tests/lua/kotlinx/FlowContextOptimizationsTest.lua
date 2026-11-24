-- Port of kotlinx.coroutines' FlowContextOptimizationsTest.
-- Dispatcher/context fusion optimizations are not-applicable (no dispatchers).
-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/FlowContextOptimizationsTest.kt@1.11.0
describe("FlowContextOptimizationsTest", function ()
    -- not-applicable: no dispatcher fusion in a single-threaded runtime.
    pending("testBaseline")

    -- not-applicable: no dispatcher fusion in a single-threaded runtime.
    pending("testFusedSameContext")

    -- not-applicable: no dispatcher fusion in a single-threaded runtime.
    pending("testFusedSameContextWithIntermediateOperators")

    -- not-applicable: no dispatcher fusion in a single-threaded runtime.
    pending("testFusedSameDispatcher")

    -- not-applicable: no dispatcher fusion in a single-threaded runtime.
    pending("testFusedManySameDispatcher")
end)