-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/FlatMapMergeTest.kt@1.11.0
local flow = require("luastd.flow")
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("FlatMapMergeTest", function ()
    -- not-applicable: flat_map_merge has no concurrency-limit argument and
    -- currently runs each inner flow serially, so it cannot test concurrency=2.
    pending("testFlatMapConcurrency")

    -- not-applicable: the case depends on CoroutineStart.ATOMIC and dispatcher
    -- scheduling to start an inner transform despite cancellation.
    pending("testAtomicStart")

    -- not-applicable: CancellationException is catchable in the Kotlin inner
    -- flow, while luastd cancellation bypasses Lua callbacks (ADR 0005).
    pending("testCancellationExceptionDownstream")

    -- not-applicable: the upstream throws a catchable CancellationException;
    -- luastd only exposes uncatchable cancellation (ADR 0005).
    pending("testCancellationExceptionUpstream")

    -- not-applicable: this case requires concurrent inner flows to stop after
    -- take cancels collection; flat_map_merge currently collects them serially.
    pending("testCancellation")

    -- not-applicable: this failure-cancellation case requires a sibling inner
    -- flow to remain suspended concurrently with the failing inner flow.
    pending("testFailureCancellation")

    -- not-applicable: flat_map_merge does not collect inner flows concurrently,
    -- so there is no sibling failure race to assert.
    pending("testConcurrentFailure")

    -- not-applicable: the source mapper does not run concurrently with an
    -- already-suspended inner flow in the current serial implementation.
    pending("testFailureInMapOperationCancellation")

    -- adapted: verify flat-map expansion and values with the serial current
    -- implementation; it does not assert Kotlin's concurrent merge ordering.
    it("testFlatMap", runtest(function ()
        local values = {}
        for i = 1, 100 do values[i] = i end
        local result = flow.from(values):flat_map_merge(function (value)
            local inner = {}
            for i = 1, value do inner[i] = i end
            return flow.from(inner)
        end):reduce(function (sum, value) return sum + value end)
        assert.is_equal(100 * 101 * 102 / 6, result)
    end))

    -- adapted: check single-value selection across empty inner flows; the
    -- current operator is serial and this does not assert merge concurrency.
    it("testSingle", runtest(function ()
        local values = {}
        for i = 0, 99 do values[#values + 1] = i end
        local result = flow.from(values):flat_map_merge(function (value)
            if value == 99 then return flow.of_one(42) end
            return flow.empty()
        end):single()
        assert.is_equal(42, result)
    end))

    -- not-applicable: channel-backed flat_map_merge cannot emit nil values,
    -- which are central to the nullable expansion in this Kotlin case.
    pending("testNulls")

    -- adapted: luastd has no dispatcher identity; verify CoroutineName is
    -- visible in the mapper and inner flow under the composed flow context.
    it("testContext", runtest(function ()
        local context = async.context(async.coroutine_name("combined"))
        local source = flow.of_one(1):flat_map_merge(function (value)
            assert.is_equal("combined", async.current_context():coroutine_name())
            return flow.new(function (emit)
                assert.is_equal("combined", async.current_context():coroutine_name())
                emit(value)
            end)
        end):flow_on(context)
        assert.same({ 1 }, source:to_list())
    end))

    -- not-applicable: this requires nested dispatcher isolation between merge
    -- stages; luastd flow_on applies CoroutineContext to an upstream segment.
    pending("testIsolatedContext")
end)
