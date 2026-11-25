-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/CombineTest.kt@1.11.0
local flow = require("luastd.flow")
local async = require("luastd.async")
local runtest = require("luastd_test").runtest

describe("CombineTransformIterableTest", function ()
    -- adapted: combineTransform over an iterable is absent; binary Flow:combine
    -- emits the single transformed value and delivers these latest pairs.
    it(
        "testCombineLatest",
        runtest(function ()
            local result = flow.from({ "a", "b", "c" }):combine(flow.from({ 1, 2, 3 }), function (a, b)
                return a .. b
            end):to_list()
            assert.same({ "a1", "b1", "b2", "c2", "c3" }, result)
        end)
    )

    -- adapted: combineTransform's reusable argument array is not exposed;
    -- verify nil remains a latest value across the binary combine boundary.
    it(
        "testNulls",
        runtest(function ()
            local nullable = flow.new(function (emit)
                emit("a")
                emit(nil)
                emit(nil)
            end)
            local result = nullable:combine(flow.from({ 1, 2, 3 }), function (a, b)
                return tostring(a) .. b
            end):to_list()
            assert.is_true(#result > 0)
            assert.is_equal("nil3", result[#result])
        end)
    )

    -- adapted: same latest-value check when the second input emits nil.
    it(
        "testNullsOther",
        runtest(function ()
            local nullable = flow.new(function (emit)
                emit(nil)
                emit(2)
                emit(nil)
            end)
            local result = flow.from({ "a", "b", "c" }):combine(nullable, function (a, b)
                return a .. tostring(b)
            end):to_list()
            assert.is_true(#result > 0)
            assert.is_equal("cnil", result[#result])
        end)
    )

    -- adapted: run the one-result transform with the binary combine operator.
    it(
        "testEmptyFlow",
        runtest(function ()
            assert.same({}, flow.empty():combine(flow.empty(), function () error("unreachable") end):to_list())
        end)
    )

    it(
        "testFirstIsEmpty",
        runtest(function ()
            assert.same({}, flow.empty():combine(flow.from({ 1 }), function () error("unreachable") end):to_list())
        end)
    )

    it(
        "testSecondIsEmpty",
        runtest(function ()
            assert.same({}, flow.from({ "a" }):combine(flow.empty(), function () error("unreachable") end):to_list())
        end)
    )

    -- adapted: each source yields cooperatively to exercise interleaved latest
    -- values; the binary transform emits one result for each delivered update.
    it(
        "testPreservingOrder",
        runtest(function ()
            local first = flow.new(function (emit)
                emit("a")
                async.yield()
                emit("b")
                async.yield()
                emit("c")
            end)
            local second = flow.new(function (emit)
                emit(1)
                async.yield()
                emit(2)
                async.yield()
                emit(3)
            end)
            local result = first:combine(second, function (a, b) return a .. b end):to_list()
            assert.same({ "a1", "b1", "b2", "c2", "c3" }, result)
        end)
    )

    -- adapted: source argument order changes task start order in Lua; verify
    -- the latest pairs for the reversed binary receiver order.
    it(
        "testPreservingOrderReversed",
        runtest(function ()
            local first = flow.new(function (emit)
                emit("a")
                async.yield()
                emit("b")
                async.yield()
                emit("c")
            end)
            local second = flow.new(function (emit)
                emit(1)
                async.yield()
                emit(2)
                async.yield()
                emit(3)
            end)
            local result = second:combine(first, function (b, a) return a .. b end):to_list()
            assert.same({ "a1", "a2", "b2", "b3", "c3" }, result)
        end)
    )

    -- adapted: combineTransform's transform runs in the collector's context;
    -- check named contexts at both flow_on sources and at the transform.
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
                first:combine(second, function (a, b) return a .. b end):on_each(function ()
                    error(failure, 0)
                end):to_list()
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
            local second = flow.new(function (emit)
                emit(1)
                error(failure, 0)
            end)
            local ok, err = pcall(function () first:combine(second, function (a, b) return a .. b end):to_list() end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
        end)
    )

    -- not-applicable: these Kotlin cases require catchable CancellationException
    -- from upstream/downstream flow code; luastd cancellation is uncatchable.
    pending("testCancellationExceptionUpstream")
    pending("testCancellationExceptionDownstream")

    -- not-applicable: Kotlin cancels a coroutine scope before combine starts;
    -- a Flow collection does not expose a separate child scope to cancel first.
    pending("testCancelledCombine")
end)
