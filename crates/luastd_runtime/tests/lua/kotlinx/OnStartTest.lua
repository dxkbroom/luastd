-- Port of kotlinx.coroutines' OnStartTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/OnStartTest.kt@1.11.0
describe("OnStartTest", function ()
    it("testEmitExample", function ()
        local started = false
        local r = flow.from({ 1, 2 }):on_start(function () started = true end):to_list()
        assert.is_true(started)
        assert.is_equal(2, #r)
    end)

    -- defer: transparency violation semantics.
    pending("testTransparencyViolation")
end)