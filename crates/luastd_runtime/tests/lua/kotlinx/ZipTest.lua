-- Port of kotlinx.coroutines' ZipTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/ZipTest.kt@1.11.0
describe("ZipTest", function ()
    it("testZip", function ()
        local f1 = flow.from({ "a", "b", "c" })
        local f2 = flow.from({ 1, 2, 3 })
        local r = f1:zip(f2, function (a, b) return a .. b end):to_list()
        assert.is_equal(3, #r)
        assert.is_equal("a1", r[1])
        assert.is_equal("b2", r[2])
        assert.is_equal("c3", r[3])
    end)

    it("testUnevenZip", function ()
        local f1 = flow.from({ "a", "b", "c", "d", "e" })
        local f2 = flow.from({ 1, 2, 3 })
        local r = f1:zip(f2, function (a, b) return a .. b end):to_list()
        assert.is_equal(3, #r)
    end)

    it("testEmptyFlows", function ()
        local r = flow.empty():zip(flow.empty(), function (a, b) return a end):to_list()
        assert.is_equal(0, #r)
    end)

    it("testEmpty", function ()
        local r = flow.empty():zip(flow.from({ 1 }), function (a, b) return a end):to_list()
        assert.is_equal(0, #r)
    end)

    it("testEmptyOther", function ()
        local r = flow.from({ "a" }):zip(flow.empty(), function (a, b) return a end):to_list()
        assert.is_equal(0, #r)
    end)

    -- defer: cancellation/error semantics.
    pending("testNulls")
    pending("testNullsOther")
    pending("testCancelWhenFlowIsDone")
    pending("testCancelWhenFlowIsDone2")
    pending("testCancelWhenFlowIsDoneReversed")
    pending("testContextIsIsolatedReversed")
    pending("testErrorInDownstreamCancelsUpstream")
    pending("testErrorCancelsSibling")
    pending("testCancellationUpstream")
    pending("testCancellationDownstream")
    pending("testCancellationOfCollector")
end)
