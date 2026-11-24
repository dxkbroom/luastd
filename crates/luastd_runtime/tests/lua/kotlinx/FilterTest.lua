-- Port of kotlinx.coroutines' FilterTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/FilterTest.kt@1.11.0
describe("FilterTest", function ()
    it("testFilter", function ()
        local r = flow.from({ 1, 2, 3, 4 }):filter(function (x) return x % 2 == 0 end):to_list()
        assert.is_equal(2, #r)
        assert.is_equal(2, r[1])
        assert.is_equal(4, r[2])
    end)

    it("testEmptyFlow", function ()
        local r = flow.empty():filter(function (x) return true end):to_list()
        assert.is_equal(0, #r)
    end)

    -- defer: error propagation semantics.
    pending("testErrorCancelsUpstream")
    pending("testFilterNot")
    pending("testEmptyFlowFilterNot")
    pending("testErrorCancelsUpstreamwFilterNot")
end)