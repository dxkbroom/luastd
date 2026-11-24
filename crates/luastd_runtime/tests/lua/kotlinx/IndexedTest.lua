-- Port of kotlinx.coroutines' IndexedTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/IndexedTest.kt@1.11.0
describe("IndexedTest", function ()
    it("testWithIndex", function ()
        local r = flow.from({ 3, 2, 1 }):with_index():to_list()
        assert.is_equal(3, #r)
        assert.is_equal(0, r[1].index)
        assert.is_equal(3, r[1].value)
        assert.is_equal(1, r[2].index)
        assert.is_equal(2, r[2].value)
        assert.is_equal(2, r[3].index)
        assert.is_equal(1, r[3].value)
    end)

    it("testWithIndexEmpty", function ()
        local r = flow.empty():with_index():to_list()
        assert.is_equal(0, #r)
    end)

    it("testCollectIndexed", function ()
        local result = {}
        flow.from({ 3, 2, 1 }):collect_indexed(function (i, v)
            table.insert(result, { index = i, value = v })
        end)
        assert.is_equal(3, #result)
        assert.is_equal(0, result[1].index)
        assert.is_equal(3, result[1].value)
    end)

    it("testCollectIndexedEmptyFlow", function ()
        flow.empty():collect_indexed(function () error("should not be called") end)
    end)
end)