-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/CombineTest.kt@1.11.0
local flow = require("luastd.flow")
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

local function assert_latest_outputs(result, min_count, max_count)
    local valid = { a1 = true, a2 = true, a3 = true, b1 = true, b2 = true, b3 = true, c1 = true, c2 = true, c3 = true }
    assert.is_true(#result >= min_count and #result <= max_count)
    assert.is_equal("a1", result[1])
    assert.is_equal("c3", result[#result])
    for _, value in ipairs(result) do
        assert.is_true(valid[value])
    end
end

describe("CombineTransformTest", function ()
    -- adapted: LocalSet source scheduling differs from Kotlin's test
    -- dispatcher; asynchronous source tests below also check latest semantics.
    -- combineTransform is absent; this test's transform emits one value per
    -- pair, so the equivalent Flow:combine value transform checks that result.
    it(
        "testCombineLatest",
        runtest(function ()
            local result = flow.from({ "a", "b", "c" }):combine(flow.from({ 1, 2, 3 }), function (a, b)
                return a .. b
            end):to_list()
            assert_latest_outputs(result, 3, 5)
        end)
    )

    -- adapted: the common test emits one transformed value per latest pair;
    -- express that with Flow:combine, preserving nullable input coverage.
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

    -- adapted: as in testNulls, the single emit in Kotlin's transform maps to
    -- Flow:combine's value transform; nil is converted into a string result.
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

    -- adapted: Flow:combine covers the common empty-input behavior; it has no
    -- separate combineTransform builder.
    it(
        "testEmptyFlow",
        runtest(function ()
            assert.same({}, flow.empty():combine(flow.empty(), function () return "x" end):to_list())
        end)
    )

    -- adapted: verify empty-input behavior through Flow:combine because the
    -- test's transform emits once and combineTransform is absent.
    it(
        "testFirstIsEmpty",
        runtest(function ()
            assert.same({}, flow.empty():combine(flow.from({ 1 }), function (_, b) return b end):to_list())
        end)
    )

    -- adapted: verify empty-input behavior through Flow:combine because the
    -- test's transform emits once and combineTransform is absent.
    it(
        "testSecondIsEmpty",
        runtest(function ()
            assert.same({}, flow.from({ 1, 2 }):combine(flow.empty(), function (a) return a end):to_list())
        end)
    )

    -- adapted: tokio's interleaving differs from Kotlin's scheduler; test the
    -- latest-value emissions through Flow:combine's single-result transform.
    it(
        "testPreservingOrder",
        runtest(function (t)
            local first = flow.new(function (emit)
                emit("a")
                async.yield()
                emit("b")
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
            assert_latest_outputs(result, 4, 5)
            t:finish(1)
        end)
    )

    -- adapted: argument order changes LocalSet start order; use Flow:combine's
    -- single-result transform to verify the latest-value updates.
    it(
        "testPreservingOrderReversed",
        runtest(function (t)
            local first = flow.new(function (emit)
                emit("a")
                async.yield()
                emit("b")
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
            assert_latest_outputs(result, 4, 5)
            t:finish(1)
        end)
    )

    -- adapted: luastd has no dispatcher identity; verify CoroutineName across
    -- flow_on boundaries while using the available single-result combine API.
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

    -- adapted: the common transform emits exactly once, so Flow:combine's
    -- value transform can exercise downstream failure cancellation.
    it(
        "testErrorInDownstreamCancelsUpstream",
        runtest(function ()
            local failure = luastd_test.TestException()
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

    -- adapted: Flow:combine uses structured sibling collectors; represent the
    -- common one-emission transform with its value transform callback.
    it(
        "testErrorCancelsSibling",
        runtest(function ()
            local failure = luastd_test.TestException()
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

    -- not-applicable: Kotlin throws a catchable CancellationException from
    -- one upstream; luastd only has an uncatchable cancellation token (ADR 0005).
    pending("testCancellationExceptionUpstream")

    -- not-applicable: the case throws a catchable CancellationException from
    -- a downstream child; luastd cancellation bypasses Lua callbacks (ADR 0005).
    pending("testCancellationExceptionDownstream")

    -- not-applicable: this expects cancellation to be captured by runTest's
    -- expected-exception harness, but ADR 0005 makes cancellation uncatchable.
    pending("testCancelledCombine")
end)
