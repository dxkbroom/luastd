-- Port of kotlinx.coroutines' OnEmptyTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/OnEmptyTest.kt@1.11.0
describe("OnEmptyTest", function ()
    it("testOnEmptyInvoked", function ()
        local invoked = false
        local r = flow.empty():on_empty(function () invoked = true end):to_list()
        assert.is_true(invoked)
        assert.is_equal(0, #r)
    end)

    it("testOnEmptyNotInvoked", function ()
        local invoked = false
        local r = flow.from({ 1 }):on_empty(function () invoked = true end):to_list()
        assert.is_false(invoked)
        assert.is_equal(1, #r)
    end)

    -- defer: cancellation/error semantics.
    pending("testOnEmptyNotInvokedOnError")
    pending("testOnEmptyNotInvokedOnCancellation")
    pending("testOnEmptyCancellation")
    pending("testTransparencyViolation")
end)
