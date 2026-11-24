-- Port of kotlinx.coroutines' ReduceTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/ReduceTest.kt@1.11.0
describe("ReduceTest", function ()
    it("testReduce", function ()
        assert.is_equal(10, flow.from({ 1, 2, 3, 4 }):reduce(function (a, v) return a + v end))
    end)

    it("testEmptyReduce", function ()
        local ok = pcall(function () flow.empty():reduce(function (a, v) return a + v end) end)
        assert.is_false(ok)
    end)

    -- defer: error/null semantics.
    pending("testErrorCancelsUpstream")
    pending("testNullableReduce")
    pending("testReduceNulls")
end)
