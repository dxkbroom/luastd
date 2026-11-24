-- Port of kotlinx.coroutines' ToCollectionTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/ToCollectionTest.kt@1.11.0
describe("ToCollectionTest", function ()
    it("testToList", function ()
        local r = flow.from({ 1, 2, 3 }):to_list()
        assert.is_equal(3, #r)
        assert.is_equal(1, r[1])
        assert.is_equal(3, r[3])
    end)

    it("testToSet", function ()
        local set = {}
        flow.from({ 1, 2, 2, 3 }):collect(function (v) set[v] = true end)
        local n = 0
        for _ in pairs(set) do
            n = n + 1
        end
        assert.is_equal(3, n)
    end)
end)
