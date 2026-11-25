-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/ChunkedTest.kt@1.11.0
local flow = require("luastd.flow")
local async = require("luastd.async")
local runtest = require("luastd_test").runtest

describe("ChunkedTest", function ()
    it(
        "testChunked",
        runtest(function ()
            local result = flow.from({ 1, 2, 3, 4, 5 }):chunked(2):to_list()
            assert.same({ { 1, 2 }, { 3, 4 }, { 5 } }, result)
        end)
    )

    it(
        "testEmpty",
        runtest(function ()
            assert.same({}, flow.empty():chunked(1):to_list())
            assert.same({}, flow.empty():chunked(2):to_list())
        end)
    )

    it(
        "testChunkedCancelled",
        runtest(function (t)
            local result = flow.new(function (emit)
                t:expect(1)
                emit(1)
                emit(2)
                t:expect(2)
            end):chunked(1):buffer():take(1):to_list()
            assert.same({ { 1 } }, result)
            t:finish(3)
        end)
    )

    it(
        "testChunkedCancelledWithSuspension",
        runtest(function (t)
            local result = flow.new(function (emit)
                t:expect(1)
                emit(1)
                async.yield()
                t:expect_unreached()
                emit(2)
            end):chunked(1):buffer():take(1):to_list()
            assert.same({ { 1 } }, result)
            t:finish(2)
        end)
    )

    -- not-applicable: the Kotlin case relies on coroutineScope cancelling a
    -- launched child when take cancels collection; Flow has no child scope.
    pending("testChunkedDoesNotIgnoreCancellation")

    it(
        "testIae",
        runtest(function ()
            for _, size in ipairs({ 0, -1, -2147483648, -2147483647 }) do
                local ok = pcall(function () flow.empty():chunked(size) end)
                assert.is_false(ok)
            end
        end)
    )

    it(
        "testSample",
        runtest(function ()
            local result = flow.from({ "a", "b", "c", "d", "e" }):chunked(2):map(function (chunk)
                return table.concat(chunk, "")
            end):to_list()
            assert.same({ "ab", "cd", "e" }, result)
        end)
    )
end)
