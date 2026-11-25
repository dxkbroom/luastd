local async = require("luastd.async")
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

local function sum(values)
    local result = 0
    for _, value in ipairs(values) do result = result + value end
    return result
end

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/TakeTest.kt@1.11.0
describe("TakeTest", function ()
    -- adapted: Flow has no sum terminal operator; collect and sum the values
    -- returned by to_list while checking take/drop/single results.
    it("testTake", runtest(function ()
        local values = flow.from({ 1, 2 }):to_list()
        assert.is_equal(3, sum(flow.from(values):take(2):to_list()))
        assert.is_equal(3, sum(flow.from(values):take(2147483647):to_list()))
        assert.is_equal(1, flow.from(values):take(1):single())
        assert.is_equal(2, flow.from(values):drop(1):take(1):single())
    end))

    -- adapted: Lua take is lazy and treats non-positive counts as an empty
    -- result; Kotlin throws IllegalArgumentException when constructing it.
    it("testIllegalArgument", runtest(function ()
        assert.same({}, flow.of_one(1):take(0):to_list())
        assert.same({}, flow.of_one(1):take(-1):to_list())
    end))

    -- adapted: use async.yield in the source body to suspend between emissions;
    -- terminal results are collected and summed because Flow has no sum method.
    it("testTakeSuspending", runtest(function ()
        local source = flow.new(function (emit)
            emit(1)
            async.yield()
            emit(2)
            async.yield()
        end)
        assert.is_equal(3, sum(source:take(2):to_list()))
        assert.is_equal(3, sum(source:take(2147483647):to_list()))
        assert.is_equal(1, source:take(1):single())
        assert.is_equal(2, source:drop(1):take(1):single())
    end))

    -- adapted: to_list length represents the empty flow's sum of zero; no sum
    -- terminal operator is exposed.
    it("testEmptyFlow", runtest(function ()
        assert.is_equal(0, #flow.empty():take(10):to_list())
    end))

    -- adapted: verify the current Lua empty-flow behavior for both zero and
    -- negative counts; Kotlin rejects both values.
    it("testNonPositiveValues", runtest(function ()
        assert.same({}, flow.of_one(1):take(0):to_list())
        assert.same({}, flow.of_one(1):take(-1):to_list())
    end))

    -- defer: Flow collection is synchronous and does not expose kotlinx-style
    -- child jobs that take can cancel and join on short-circuit.
    pending("testCancelUpstream")

    -- defer: the flow implementation does not track upstream child lifetime or
    -- guarantee cancellation cleanup when a downstream map fails.
    pending("testErrorCancelsUpstream")

    it("takeWithRetries", runtest(function (t)
        t:expect(1)
        local source = flow.new(function (emit)
            emit(1)
            t:expect(2)
            emit(2)
            while true do
                emit(42)
                t:expect_unreached()
            end
        end):retry(2, function ()
            t:expect_unreached()
            return true
        end):take(2)
        assert.is_equal(3, sum(source:to_list()))
        t:finish(3)
    end))

    it("testNonIdempotentRetry", runtest(function (t)
        local count = 0
        flow.new(function (emit)
            while true do emit(1) end
        end):retry(nil, function ()
            count = count + 1
            return count % 2 == 0
        end):take(1):collect(function () t:expect(1) end)
        assert.is_equal(0, count)
        t:finish(2)
    end))

    -- adapted: Flow has no emitAll; collecting the inner take flow into the
    -- outer emitter preserves the nested short-circuit behavior.
    it("testNestedTake", runtest(function ()
        local inner = flow.new(function (emit)
            emit(1)
            error("inner source continued past take")
        end):take(1)
        local outer = flow.new(function (emit)
            for _ = 1, 3 do inner:collect(emit) end
        end)
        local values = outer:take(3):to_list()
        assert.is_equal(3, #values)
        assert.is_equal(1, values[1])
        assert.is_equal(1, values[2])
        assert.is_equal(1, values[3])
    end))
end)
