-- Port of kotlinx.coroutines' FoldTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/FoldTest.kt@1.11.0
describe("FoldTest", function ()
    it("testFold", function ()
        assert.is_equal(10, flow.from({ 1, 2, 3, 4 }):fold(0, function (a, v) return a + v end))
    end)

    it("testEmptyFold", function ()
        assert.is_equal(5, flow.empty():fold(5, function (a, v) return a + v end))
    end)

    -- defer: error propagation semantics.
    pending("testErrorCancelsUpstream")
end)
