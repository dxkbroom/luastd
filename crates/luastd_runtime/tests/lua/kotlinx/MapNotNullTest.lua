-- Port of kotlinx.coroutines' MapNotNullTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/MapNotNullTest.kt@1.11.0
describe("MapNotNullTest", function ()
    it("testMap", function ()
        local r = flow.from({ 1, 2, 3 }):map_not_null(function (x)
            if x == 2 then return nil end
            return x * 2
        end):to_list()
        assert.is_equal(2, #r)
        assert.is_equal(2, r[1])
        assert.is_equal(6, r[2])
    end)

    it("testEmptyFlow", function ()
        local r = flow.empty():map_not_null(function (x) return x end):to_list()
        assert.is_equal(0, #r)
    end)

    -- defer: error propagation semantics.
    pending("testErrorCancelsUpstream")
end)