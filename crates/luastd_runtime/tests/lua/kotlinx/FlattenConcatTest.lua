-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/FlattenConcatTest.kt@1.11.0
local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

describe("FlattenConcatTest", function ()
    -- adapted: Kotlin checks flattenConcat's concurrency of one; use
    -- flat_map_concat and a downstream take to verify its sequential fast path.
    it("testFlatMapConcurrency", runtest(function ()
        local started = 0
        local result = flow.from({ 1, 2, 3 }):flat_map_concat(function (value)
            return flow.new(function (emit)
                started = started + 1
                emit(value)
                async.delay(math.huge)
            end)
        end):take(1):to_list()
        assert.same({ 1 }, result)
        assert.is_equal(1, started)
    end))

    -- not-applicable: Kotlin catches CancellationException from an inner flow;
    -- luastd cancellation bypasses catchable test assertions (ADR 0005).
    pending("testCancellation")

    -- adapted: flattenConcat is absent; flat_map_concat with the same mapper
    -- verifies the supported sequential flattening results.
    it("testFlatMap", runtest(function ()
        local inputs = {}
        for value = 1, 100 do inputs[#inputs + 1] = value end
        local result = flow.from(inputs):flat_map_concat(function (value)
            local inner = {}
            for item = 1, value do inner[#inner + 1] = item end
            return flow.from(inner)
        end):to_list()
        local sum = 0
        for _, value in ipairs(result) do sum = sum + value end
        assert.is_equal(171700, sum)
    end))

    -- adapted: use flat_map_concat instead of the absent flattenConcat API;
    -- exactly one inner flow emits a value, so the single result is preserved.
    it("testSingle", runtest(function ()
        local inputs = {}
        for value = 0, 99 do inputs[#inputs + 1] = value end
        local result = flow.from(inputs):flat_map_concat(function (value)
            if value == 99 then return flow.of_one(42) end
            return flow.empty()
        end):to_list()
        assert.same({ 42 }, result)
    end))

    -- not-applicable: Channel:send rejects nil, and inner nil emissions cannot
    -- pass through flat_map_concat's channel-based flow combinators.
    pending("testNulls")

    -- adapted: use CoroutineName in place of NamedDispatchers to assert that
    -- the mapper and inner flow inherit each collection's flow_on context.
    it("testContext", runtest(function ()
        local captured = {}
        local mapped = flow.from({ 1 }):flat_map_concat(function (value)
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

    -- not-applicable: flow_on runs synchronous collection inline without the
    -- dispatcher boundary needed to isolate nested inner/outer mapper contexts.
    pending("testIsolatedContext")
end)
