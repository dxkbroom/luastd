-- Port of kotlinx.coroutines' CountTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/CountTest.kt@1.11.0
describe("CountTest", function ()
    it("testCount", function ()
        assert.is_equal(3, flow.from({ 1, 2, 3 }):count())
        assert.is_equal(0, flow.empty():count())
    end)

    it("testNoValues", function ()
        assert.is_equal(0, flow.empty():count())
    end)

    -- defer: exception propagation semantics.
    pending("testException")
    pending("testExceptionAfterValue")
end)