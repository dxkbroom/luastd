-- Port of kotlinx.coroutines' CombineTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/CombineTest.kt@1.11.0
describe("CombineTest", function ()
    it("testCombineLatest", function ()
        local r = flow.from({ 1, 2 }):combine(flow.from({ 10, 20 }), function (a, b) return a + b end):to_list()
        assert.is_equal(2, #r)
    end)

    pending("testNulls")
    pending("testNullsOther")
    it("testEmptyFlow", function ()
        local r = flow.empty():combine(flow.from({ 1 }), function (a, b) return a end):to_list()
        assert.is_equal(0, #r)
    end)

    it("testFirstIsEmpty", function ()
        local r = flow.empty():combine(flow.from({ 1, 2 }), function (a, b) return b end):to_list()
        assert.is_equal(0, #r)
    end)

    it("testSecondIsEmpty", function ()
        local r = flow.from({ 1, 2 }):combine(flow.empty(), function (a, b) return a end):to_list()
        assert.is_equal(0, #r)
    end)

    -- defer: cancellation/error/context semantics.
    pending("testPreservingOrder")
    pending("testPreservingOrderReversed")
    pending("testContextIsIsolated")
    pending("testErrorInDownstreamCancelsUpstream")
    pending("testErrorCancelsSibling")
    pending("testCancellationExceptionUpstream")
    pending("testCancellationExceptionDownstream")
    pending("testCancelledCombine")
end)
