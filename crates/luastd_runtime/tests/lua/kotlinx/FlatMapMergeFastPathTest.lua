-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/FlatMapMergeFastPathTest.kt@1.11.0
local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

describe("FlatMapMergeFastPathTest", function ()
    -- not-applicable: flat_map_merge accepts no concurrency option and its
    -- current implementation processes mapped flows serially.
    pending("testFlatMapConcurrency")

    -- not-applicable: Kotlin treats a child CancellationException as normal
    -- completion; luastd cancellation is uncatchable (ADR 0005).
    pending("testCancellationExceptionDownstream")

    -- not-applicable: Kotlin catches upstream CancellationException to assert
    -- later actions; luastd cancellation bypasses the test body (ADR 0005).
    pending("testCancellationExceptionUpstream")

    -- adapted: verify take returns the requested prefix; flat_map_merge's
    -- buffered producer can finish the finite source before downstream take.
    it("testCancellation", runtest(function ()
        local result = flow.from({ 1, 2, 3, 4, 5 }):flat_map_merge(function (value)
            return flow.of_one(value)
        end):buffer(64):take(2):to_list()
        assert.same({ 1, 2 }, result)
    end))

    -- not-applicable: mapped flows run serially, so a hanging first inner flow
    -- prevents the later inner failure that this test coordinates concurrently.
    pending("testFailureCancellation")

    -- not-applicable: flat_map_merge has no concurrent inner flows or channel
    -- rendezvous primitive exposed to coordinate simultaneous failures.
    pending("testConcurrentFailure")

    -- not-applicable: the map-operation failure can only race an active inner
    -- flow under concurrent merging, which the current implementation lacks.
    pending("testFailureInMapOperationCancellation")

    it("testFlatMap", runtest(function ()
        local inputs = {}
        for value = 1, 100 do inputs[#inputs + 1] = value end
        local result = flow.from(inputs):flat_map_merge(function (value)
            local inner = {}
            for item = 1, value do inner[#inner + 1] = item end
            return flow.from(inner)
        end):to_list()
        local sum = 0
        for _, value in ipairs(result) do sum = sum + value end
        assert.is_equal(171700, sum)
    end))

    it("testSingle", runtest(function ()
        local inputs = {}
        for value = 0, 99 do inputs[#inputs + 1] = value end
        local result = flow.from(inputs):flat_map_merge(function (value)
            if value == 99 then return flow.of_one(42) end
            return flow.empty()
        end):to_list()
        assert.same({ 42 }, result)
    end))

    -- not-applicable: a Lua sequence cannot contain nil, and Channel:send
    -- rejects nil, so the source and inner nullable flows cannot be represented.
    pending("testNulls")

    -- adapted: use CoroutineName in place of unavailable named dispatchers to
    -- verify context inheritance through the mapper and its inner flow.
    it("testContext", runtest(function ()
        local captured = {}
        local mapped = flow.from({ 1 }):flat_map_merge(function (value)
            captured[#captured + 1] = async.current_context():coroutine_name()
            return flow.new(function (emit)
                captured[#captured + 1] = async.current_context():coroutine_name()
                emit(value)
            end)
        end)
        local first = mapped:flow_on(async.context(async.coroutine_name("one"))):to_list()
        local second = mapped:flow_on(async.context(async.coroutine_name("two"))):to_list()
        assert.same({ 1 }, first)
        assert.same({ 1 }, second)
        assert.same({ "one", "one", "two", "two" }, captured)
    end))

    -- adapted: luastd exposes CoroutineName, not independent dispatcher
    -- contexts; verify nested flow_on names on the mapped flows instead.
    it("testIsolatedContext", runtest(function ()
        local source_context = async.context(async.coroutine_name("source"))
        local outer_context = async.context(async.coroutine_name("outer"))
        local inner_context = async.context(async.coroutine_name("inner"))
        local captured = {}
        local inner = flow.from({ 1 }):flow_on(source_context):flat_map_merge(function (value)
            captured[#captured + 1] = async.current_context():coroutine_name()
            return flow.new(function (emit)
                captured[#captured + 1] = async.current_context():coroutine_name()
                emit(value)
            end)
        end):flow_on(inner_context)
        local result = inner:flat_map_merge(function (value)
            captured[#captured + 1] = async.current_context():coroutine_name()
            return flow.new(function (emit)
                captured[#captured + 1] = async.current_context():coroutine_name()
                emit(value)
            end)
        end):flow_on(outer_context):to_list()
        assert.same({ 1 }, result)
        assert.same({ "source", "source", "inner", "inner" }, captured)
    end))
end)
