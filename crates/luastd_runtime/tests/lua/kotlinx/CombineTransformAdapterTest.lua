-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/CombineTest.kt@1.11.0
local flow = require("luastd.flow")
local async = require("luastd.async")
local runtest = require("luastd_test").runtest

describe("CombineTransformAdapterTest", function ()
    -- adapted: combine_transform is absent; use combine, which dispatches
    -- every source update rather than coalescing
    -- updates in the Kotlin test scheduler; assert each resulting latest pair.
    it(
        "testCombineLatest",
        runtest(function ()
            local result = flow.from({ "a", "b", "c" }):combine(flow.from({ 1, 2, 3 }), function (a, b)
                return a .. b
            end):to_list()
            assert.same({ "a1", "b1", "b2", "c2", "c3" }, result)
        end)
    )

    -- adapted: use combine because combine_transform is absent; nil is
    -- preserved as a latest value, while luastd delivers the
    -- extra intermediate pairs produced by its source scheduling.
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
            assert.same({ "a1", "nil1", "nil2", "nil2", "nil3" }, result)
        end)
    )

    -- adapted: combine_transform is absent; use combine and account for the
    -- same scheduling difference for a nullable second flow.
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
            assert.same({ "anil", "bnil", "b2", "c2", "cnil" }, result)
        end)
    )

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

    -- adapted: combine_transform is absent; use combine and add cooperative
    -- yields between Lua source emissions to expose
    -- interleaved latest updates; the scheduler's emitted sequence differs.
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

    -- adapted: combine_transform is absent; use combine with the inputs
    -- reversed and the same cooperative scheduling adaptation.
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

    -- not-applicable: luastd has no dispatcher context element, so source and
    -- transform execution cannot be checked against isolated dispatcher names.
    pending("testContextIsIsolated")

    -- adapted: combine_transform is absent; use combine's single-result
    -- transform callback while checking downstream failure cancellation.
    it(
        "testErrorInDownstreamCancelsUpstream",
        runtest(function ()
            local failure = require("luastd_test").TestException()
            local first_cancelled = false
            local second_cancelled = false
            local first = flow.new(function (emit)
                async.finally(function ()
                    emit("a")
                    async.await_cancellation()
                end, function () first_cancelled = true end)
            end)
            local second = flow.new(function (emit)
                async.finally(function ()
                    emit(1)
                    async.await_cancellation()
                end, function () second_cancelled = true end)
            end)
            local combined = first:combine(second, function (a, b) return a .. b end):on_each(function ()
                error(failure, 0)
            end)
            local ok, err = pcall(function () combined:to_list() end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
            assert.is_true(first_cancelled)
            assert.is_true(second_cancelled)
        end)
    )

    -- adapted: combine_transform is absent; use combine's single-result
    -- transform callback while checking sibling cancellation.
    it(
        "testErrorCancelsSibling",
        runtest(function ()
            local failure = require("luastd_test").TestException()
            local sibling_cancelled = false
            local first = flow.new(function (emit)
                async.finally(function ()
                    emit("a")
                    async.await_cancellation()
                end, function () sibling_cancelled = true end)
            end)
            local second = flow.new(function (emit)
                emit(1)
                error(failure, 0)
            end)
            local ok, err = pcall(function ()
                first:combine(second, function (a, b) return a .. b end):to_list()
            end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
            assert.is_true(sibling_cancelled)
        end)
    )

    -- not-applicable: Kotlin catches these CancellationExceptions to assert
    -- follow-up actions; luastd cancellation is uncatchable (ADR 0005).
    pending("testCancellationExceptionUpstream")
    pending("testCancellationExceptionDownstream")

    -- not-applicable: this cancels the runTest scope and catches that
    -- cancellation outside coroutineScope; luastd cancellation is uncatchable
    -- by the test harness (ADR 0005).
    pending("testCancelledCombine")
end)
