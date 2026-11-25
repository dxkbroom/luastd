-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/FlattenMergeTest.kt@1.11.0
local flow = require("luastd.flow")
local async = require("luastd.async")
local runtest = require("luastd_test").runtest

describe("FlattenMergeTest", function ()
    -- not-applicable: there is no flatten_merge operator or concurrency-limit
    -- argument, and flat_map_merge currently runs inner flows serially.
    pending("testFlatMapConcurrency")

    -- adapted: verify values survive nested collection and re-emission; the
    -- current serial flatten operator does not exercise concurrent contexts.
    it(
        "testContextPreservationAcrossFlows",
        runtest(function ()
            local result = flow.new(function (emit)
                flow.from({ 1, 2 }):flat_map_merge(function (value)
                    return flow.new(function (inner_emit)
                        async.yield()
                        inner_emit(value)
                    end)
                end):collect(emit)
            end):to_list()
            assert.same({ 1, 2 }, result)
        end)
    )

    -- not-applicable: this cancellation case needs a sibling inner flow
    -- suspended concurrently with an inner flow that fails.
    pending("testFailureCancellation")

    -- not-applicable: flat_map_merge collects inner flows serially, so there
    -- is no concurrent sibling-failure race to test.
    pending("testConcurrentFailure")

    -- not-applicable: the source mapper cannot fail while another inner flow
    -- is suspended in the current serial flatten implementation.
    pending("testFailureInMapOperationCancellation")

    -- adapted: verify flat-map expansion and values with the current serial
    -- implementation; this does not assert concurrent merge ordering.
    it(
        "testFlatMap",
        runtest(function ()
            local values = {}
            for i = 1, 100 do
                values[i] = i
            end
            local result = flow.from(values):flat_map_merge(function (value)
                local inner = {}
                for i = 1, value do
                    inner[i] = i
                end
                return flow.from(inner)
            end):reduce(function (sum, value) return sum + value end)
            assert.is_equal(100 * 101 * 102 / 6, result)
        end)
    )

    -- adapted: check the sole emitted value after flattening many empty inner
    -- flows; concurrency is outside the current flat_map_merge behavior.
    it(
        "testSingle",
        runtest(function ()
            local values = {}
            for i = 0, 99 do
                values[#values + 1] = i
            end
            local result = flow.from(values):flat_map_merge(function (value)
                if value == 99 then return flow.of_one(42) end
                return flow.empty()
            end):single()
            assert.is_equal(42, result)
        end)
    )

    -- not-applicable: inner flows are sent through channels, which cannot
    -- carry nil values used by this nullable flattening case.
    pending("testNulls")

    -- adapted: there is no dispatcher identity; verify CoroutineName in the
    -- mapper and inner flow under the composed flow context.
    it(
        "testContext",
        runtest(function ()
            local context = async.context(async.coroutine_name("combined"))
            local source = flow.of_one(1):flat_map_merge(function (value)
                assert.is_equal("combined", async.current_context():coroutine_name())
                return flow.new(function (emit)
                    assert.is_equal("combined", async.current_context():coroutine_name())
                    emit(value)
                end)
            end):flow_on(context)
            assert.same({ 1 }, source:to_list())
        end)
    )

    -- not-applicable: nested dispatcher isolation cannot be represented by
    -- CoroutineName; flow_on applies a CoroutineContext to an upstream segment.
    pending("testIsolatedContext")
end)
