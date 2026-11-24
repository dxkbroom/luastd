-- Port of kotlinx.coroutines' SingleTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/SingleTest.kt@1.11.0
describe("SingleTest", function ()
    it("testSingle", function ()
        assert.is_equal(1, flow.from({ 1 }):single())
    end)

    it("testMultipleValues", function ()
        local ok = pcall(function () flow.from({ 1, 2 }):single() end)
        assert.is_false(ok)
    end)

    -- defer: nil elements are not representable in a Lua table (ipairs stops at nil).
    it("testNoValues", function ()
        local ok = pcall(function () flow.empty():single() end)
        assert.is_false(ok)
    end)

    pending("testException")
    pending("testExceptionAfterValue")
    pending("testNullableSingle")

    pending("testBadClass")
    it("testSingleNoWait", function ()
        assert.is_equal(1, flow.from({ 1 }):single())
    end)

    -- defer: exception propagation semantics.
end)
