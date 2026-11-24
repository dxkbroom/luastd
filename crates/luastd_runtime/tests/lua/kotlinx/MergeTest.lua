-- Port of kotlinx.coroutines' MergeTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/MergeTest.kt@1.11.0
describe("MergeTest", function ()
    it("testMerge", function ()
        local r = flow.merge({ flow.from({ 1, 2 }), flow.from({ 3, 4 }) }):to_list()
        assert.is_equal(4, #r)
    end)

    it("testSingle", function ()
        local r = flow.merge({ flow.from({ 1, 2 }) }):to_list()
        assert.is_equal(2, #r)
        assert.is_equal(1, r[1])
    end)

    -- defer: cancellation/context semantics.
    pending("testContext")
    pending("testIsolatedContext")
    pending("testNulls")
    pending("testOneSourceCancelled")
    pending("testOneSourceCancelledNonFused")
end)
