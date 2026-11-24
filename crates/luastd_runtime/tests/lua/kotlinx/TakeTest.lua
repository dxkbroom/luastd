-- Port of kotlinx.coroutines' TakeTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/TakeTest.kt@1.11.0
describe("TakeTest", function ()
    it("testTake", function ()
        local r = flow.from({ 1, 2, 3, 4 }):take(2):to_list()
        assert.is_equal(2, #r)
        assert.is_equal(1, r[1])
        assert.is_equal(2, r[2])
    end)

    it("testEmptyFlow", function ()
        local r = flow.empty():take(2):to_list()
        assert.is_equal(0, #r)
    end)

    it("testNonPositiveValues", function ()
        local r = flow.from({ 1, 2, 3 }):take(0):to_list()
        assert.is_equal(0, #r)
    end)

    -- defer: cancellation/error semantics.
    pending("testCancelUpstream")
    pending("testErrorCancelsUpstream")
    pending("testIllegalArgument")
    pending("testNestedTake")
    pending("testNonIdempotentRetry")
    pending("testTakeSuspending")
    pending("takeWithRetries")
end)