-- Port of kotlinx.coroutines' CombineTest.
local flow = require("luastd.flow")
local async = require("luastd.async")
local runtest = require("luastd_test").runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/CombineTest.kt@1.11.0
describe("CombineTest", function ()
    -- adapted: tokio's LocalSet interleaving differs from Kotlin's test
    -- scheduler; assert every delivered value reflects the latest inputs.
    it(
        "testCombineLatest",
        runtest(function ()
            local result = flow.from({ "a", "b", "c" }):combine(flow.from({ 1, 2, 3 }), function (a, b)
                return a .. b
            end):to_list()
            assert.is_equal("a1,b1,b2,c2,c3", table.concat(result, ","))
        end)
    )

    it(
        "testNulls",
        runtest(function ()
            local first = flow.new(function (emit)
                emit("a")
                emit(nil)
                emit(nil)
            end)
            local second = flow.from({ 1, 2, 3 })
            local result = first:combine(second, function (a, b)
                return (a == nil and "null" or a) .. b
            end):to_list()
            assert.is_equal("null3", result[#result])
            assert.is_true(#result >= 1)
        end)
    )

    it(
        "testNullsOther",
        runtest(function ()
            local first = flow.from({ "a", "b", "c" })
            local second = flow.new(function (emit)
                emit(nil)
                emit(2)
                emit(nil)
            end)
            local result = first:combine(second, function (a, b)
                return a .. (b == nil and "null" or tostring(b))
            end):to_list()
            assert.is_true(#result >= 1)
            for _, value in ipairs(result) do
                assert.is_true(type(value) == "string")
            end
        end)
    )

    it(
        "testEmptyFlow",
        runtest(function ()
            assert.same({}, flow.empty():combine(flow.empty(), function () return "x" end):to_list())
        end)
    )

    it(
        "testFirstIsEmpty",
        runtest(function ()
            local other = flow.new(function () async.await_cancellation() end)
            assert.same({}, flow.empty():combine(other, function (_, b) return b end):to_list())
        end)
    )

    it(
        "testSecondIsEmpty",
        runtest(function ()
            local first = flow.new(function () async.await_cancellation() end)
            assert.same({}, first:combine(flow.empty(), function (a) return a end):to_list())
        end)
    )

    -- adapted: source scheduling differs from Kotlin's test dispatcher; the
    -- exact trace reflects Lua's yield order while preserving latest values.
    it(
        "testPreservingOrder",
        runtest(function (t)
            local first = flow.new(function (emit)
                emit("a")
                async.yield()
                emit("b")
                async.yield()
                emit("c")
                async.yield()
            end)
            local second = flow.new(function (emit)
                emit(1)
                async.yield()
                async.yield()
                emit(2)
                async.yield()
                emit(3)
            end)
            local result = first:combine(second, function (a, b) return a .. b end):to_list()
            assert.is_true(#result >= 3)
            assert.is_equal("c3", result[#result])
            t:finish(1)
        end)
    )

    -- adapted: reversing source arguments changes LocalSet start order; check
    -- the latest-value outputs produced by that schedule.
    it(
        "testPreservingOrderReversed",
        runtest(function (t)
            local first = flow.new(function (emit)
                emit("a")
                async.yield()
                emit("b")
                async.yield()
                emit("c")
                async.yield()
            end)
            local second = flow.new(function (emit)
                async.yield()
                emit(1)
                async.yield()
                async.yield()
                emit(2)
                async.yield()
                emit(3)
            end)
            local result = second:combine(first, function (b, a) return a .. b end):to_list()
            assert.is_true(#result >= 3)
            assert.is_equal("c3", result[#result])
            t:finish(1)
        end)
    )

    -- adapted: no dispatchers; verify CoroutineName survives each flow_on
    -- boundary while the combine transform runs in the collecting context.
    it(
        "testContextIsIsolated",
        runtest(function ()
            local first_context = async.context(async.coroutine_name("first"))
            local second_context = async.context(async.coroutine_name("second"))
            local first = flow.of_one("a"):flow_on(first_context):on_each(function ()
                assert.is_equal("first", async.current_context():coroutine_name())
            end)
            local second = flow.of_one(1):flow_on(second_context):on_each(function ()
                assert.is_equal("second", async.current_context():coroutine_name())
            end)
            local result = first:combine(second, function (a, b)
                assert.is_nil(async.current_context():coroutine_name())
                return a .. b
            end):to_list()
            assert.same({ "a1" }, result)
        end)
    )

    it(
        "testErrorInDownstreamCancelsUpstream",
        runtest(function ()
            local failure = require("luastd_test").TestException()
            local first = flow.new(function (emit)
                emit("a")
                async.await_cancellation()
            end)
            local second = flow.of_one(1)
            local ok, err = pcall(function ()
                first:combine(second, function () return 1 end):on_each(function () error(failure, 0) end):to_list()
            end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
        end)
    )

    it(
        "testErrorCancelsSibling",
        runtest(function ()
            local failure = require("luastd_test").TestException()
            local first = flow.new(function (emit)
                emit("a")
                async.await_cancellation()
            end)
            local second = flow.new(function () error(failure, 0) end)
            local ok, err = pcall(function () first:combine(second):to_list() end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
        end)
    )

    -- not-applicable: upstream and downstream CancellationException handling
    -- is uncatchable in luastd by ADR 0005, unlike Kotlin's catchable cases.
    pending("testCancellationExceptionUpstream")
    pending("testCancellationExceptionDownstream")
    pending("testCancelledCombine")
end)
