-- Port of kotlinx.coroutines' ZipTest.
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/ZipTest.kt@1.11.0
describe("ZipTest", function ()
    it(
        "testZip",
        runtest(function ()
            local first = flow.from({ "a", "b", "c" })
            local second = flow.from({ 1, 2, 3 })
            local result = first:zip(second, function (a, b) return a .. b end):to_list()
            assert.same({ "a1", "b2", "c3" }, result)
        end)
    )

    it(
        "testUnevenZip",
        runtest(function ()
            local first = flow.from({ "a", "b", "c", "d", "e" })
            local second = flow.from({ 1, 2, 3 })
            local forward = first:zip(second, function (a, b) return a .. b end):to_list()
            local reverse = second:zip(first, function (a, b) return b .. a end):to_list()
            assert.same({ "a1", "b2", "c3" }, forward)
            assert.same({ "a1", "b2", "c3" }, reverse)
        end)
    )

    it(
        "testEmptyFlows",
        runtest(function ()
            local result = flow.empty():zip(flow.empty(), function (a, b) return a .. b end):to_list()
            assert.same({}, result)
        end)
    )

    it(
        "testEmpty",
        runtest(function ()
            local result = flow.empty():zip(flow.from({ 1 }), function (a, b) return a end):to_list()
            assert.same({}, result)
        end)
    )

    it(
        "testEmptyOther",
        runtest(function ()
            local result = flow.from({ "a" }):zip(flow.empty(), function (a, b) return a end):to_list()
            assert.same({}, result)
        end)
    )

    -- adapted: a callback-built flow emits nil directly; Kotlin's String? plus
    -- rendering is represented with Lua's literal "null".
    it(
        "testNulls",
        runtest(function ()
            local first = flow.new(function (emit)
                emit("a")
                emit(nil)
                emit(nil)
                emit("d")
            end)
            local result = first:zip(flow.from({ 1, 2, 3 }), function (value, number)
                return (value == nil and "null" or value) .. tostring(number)
            end):to_list()
            assert.same({ "a1", "null2", "null3" }, result)
        end)
    )

    -- adapted: a callback-built flow emits nil directly; Kotlin's String plus
    -- rendering is represented with Lua's literal "null".
    it(
        "testNullsOther",
        runtest(function ()
            local second = flow.new(function (emit)
                emit(1)
                emit(nil)
                emit(nil)
                emit(2)
            end)
            local result = flow.from({ "a", "b", "c" }):zip(second, function (value, number)
                return value .. (number == nil and "null" or tostring(number))
            end):to_list()
            assert.same({ "a1", "bnull", "cnull" }, result)
        end)
    )

    -- defer: zip materializes both synchronous sources before pairing; it has no
    -- coroutine children to cancel when the other side completes.
    pending("testCancelWhenFlowIsDone")
    pending("testCancelWhenFlowIsDone2")
    pending("testCancelWhenFlowIsDoneReversed")

    -- defer: flow_on is an identity in the synchronous Flow model, so dispatcher
    -- isolation and context-preserving concurrent source collection are absent.
    pending("testContextIsIsolatedReversed")

    -- defer: zip has no structured child jobs; downstream failure cannot cancel
    -- active upstream collection or its sibling as Kotlin's operator requires.
    pending("testErrorInDownstreamCancelsUpstream")
    pending("testErrorCancelsSibling")

    -- defer: synchronous zip cannot observe coroutine cancellation while
    -- upstream values are collected or emitted.
    pending("testCancellationUpstream")
    pending("testCancellationDownstream")
    pending("testCancellationOfCollector")
end)
