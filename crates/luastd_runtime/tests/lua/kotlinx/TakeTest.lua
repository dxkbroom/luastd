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

    -- adapted: Kotlin IllegalArgumentException is luastd's InvalidArgument kind.
    it("testIllegalArgument", runtest(function ()
        for _, count in ipairs({ 0, -1 }) do
            local ok, err = pcall(function () flow.of_one(1):take(count) end)
            assert.is_false(ok)
            assert.is_equal("InvalidArgument", err.kind)
        end
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

    -- adapted: verify construction-time InvalidArgument for both zero and
    -- negative counts, matching Kotlin's IllegalArgumentException contract.
    it("testNonPositiveValues", runtest(function ()
        for _, count in ipairs({ 0, -1 }) do
            local ok, err = pcall(function () flow.of_one(1):take(count) end)
            assert.is_false(ok)
            assert.is_equal("InvalidArgument", err.kind)
        end
    end))

    -- adapted: use a structured child completion hook to observe upstream
    -- cancellation after take emits its first value and short-circuits.
    it("testCancelUpstream", runtest(function ()
        local cancelled = false
        local source = flow.new(function (emit)
            async.scope(function (scope)
                local child = scope:launch(function () async.delay(math.huge) end)
                child:on_cancel(function () cancelled = true end)
                emit(1)
            end)
        end)
        assert.is_equal(1, source:take(1):single())
        assert.is_true(cancelled)
    end))

    -- adapted: use a structured child completion hook to verify cleanup when
    -- a downstream map throws and catch emits the replacement value.
    it("testErrorCancelsUpstream", runtest(function ()
        local cancelled = false
        local failure = luastd_test.TestException()
        local source = flow.new(function (emit)
            async.scope(function (scope)
                local child = scope:launch(function () async.delay(math.huge) end)
                child:on_cancel(function () cancelled = true end)
                emit(1)
            end)
        end):take(2):map(function () error(failure, 0) end):catch(function (emit, err)
            assert.is_true(rawequal(failure, err))
            emit(42)
        end)
        assert.is_equal(42, source:single())
        assert.is_true(cancelled)
    end))

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
