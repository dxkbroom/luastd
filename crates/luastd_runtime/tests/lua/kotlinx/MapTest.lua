-- Port of kotlinx.coroutines' MapTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/MapTest.kt@1.11.0
describe("MapTest", function ()
    it("testMap", function ()
        local r = flow.from({ 1, 2, 3 }):map(function (x) return x * 2 end):to_list()
        assert.is_equal(3, #r)
        assert.is_equal(2, r[1])
        assert.is_equal(4, r[2])
        assert.is_equal(6, r[3])
    end)

    it("testEmptyFlow", function ()
        local r = flow.empty():map(function (x) return x end):to_list()
        assert.is_equal(0, #r)
    end)

    -- defer: error propagation semantics.
    pending("testErrorCancelsUpstream")
end)