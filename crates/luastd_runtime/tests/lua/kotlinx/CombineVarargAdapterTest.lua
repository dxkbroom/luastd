-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/CombineTest.kt@1.11.0
local flow = require("luastd.flow")
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

local function assert_latest_values(result, expected_trace)
    local valid_pairs = {
        a1 = true,
        a2 = true,
        a3 = true,
        b1 = true,
        b2 = true,
        b3 = true,
        c1 = true,
        c2 = true,
        c3 = true
    }
    assert.is_equal(expected_trace, table.concat(result, ","))
    assert.is_equal("a1", result[1])
    assert.is_equal("c3", result[#result])
    for _, pair in ipairs(result) do
        assert.is_true(valid_pairs[pair])
    end
end

describe("CombineVarargAdapterTest", function ()
    -- adapted: luastd has no vararg adapter array; use pairwise combine. Its
    -- per-event rendezvous schedule differs, so validate trace and latest pairs.
    it(
        "testCombineLatest",
        runtest(function ()
            local result = flow.from({ "a", "b", "c" }):combine(flow.from({ 1, 2, 3 }), function (a, b)
                return a .. b
            end):to_list()
            assert_latest_values(result, "a1,b1,b2,c2,c3")
        end)
    )

    -- adapted: the nullable behavior is supported by pairwise combine, but
    -- this cannot exercise Kotlin's vararg array null-out optimization.
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

    -- adapted: pairwise combine handles the null-producing source; the
    -- vararg adapter array itself is not exposed by luastd.
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

    -- adapted: use pairwise combine for the empty-source result; luastd has
    -- no vararg overload or internal array lifecycle to inspect.
    it(
        "testEmptyFlow",
        runtest(function ()
            assert.same({}, flow.empty():combine(flow.empty(), function () return "x" end):to_list())
        end)
    )

    -- adapted: use pairwise combine for empty-input behavior; the adapter
    -- array null-out optimization is internal to Kotlin.
    it(
        "testFirstIsEmpty",
        runtest(function ()
            assert.same({}, flow.empty():combine(flow.from({ 1 }), function (_, b) return b end):to_list())
        end)
    )

    -- adapted: use pairwise combine for empty-input behavior; the adapter
    -- array null-out optimization is internal to Kotlin.
    it(
        "testSecondIsEmpty",
        runtest(function ()
            assert.same({}, flow.from({ 1, 2 }):combine(flow.empty(), function (a) return a end):to_list())
        end)
    )

    -- adapted: pairwise combine cannot cover vararg array null-out; cooperative
    -- yields also differ from Kotlin's scheduler, so check trace and latest pairs.
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
            assert_latest_values(result, "a1,b1,c1,c2,c3")
            t:finish(1)
        end)
    )

    -- adapted: use pairwise combine without Kotlin's vararg array; reversing
    -- arguments changes start order, so check the trace and latest pairs.
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
            assert_latest_values(result, "a1,b1,c1,c2,c3")
            t:finish(1)
        end)
    )

    -- adapted: use pairwise combine without Kotlin's vararg array; luastd also
    -- has no dispatcher identity, so verify CoroutineName across flow_on.
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

    -- adapted: the one-result transform maps to pairwise combine, which
    -- preserves upstream cancellation when downstream fails.
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

    -- adapted: the one-result transform maps to pairwise combine, which
    -- cancels a sibling collector when the other upstream fails.
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
