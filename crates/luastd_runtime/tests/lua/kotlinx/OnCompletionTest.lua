-- Port of kotlinx.coroutines' OnCompletionTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/OnCompletionTest.kt@1.11.0
describe("OnCompletionTest", function ()
    it("testOnCompletion", function ()
        local completed = false
        flow.from({ 1, 2 }):on_completion(function (err)
            completed = true
            assert.is_nil(err)
        end):to_list()
        assert.is_true(completed)
    end)

    pending("testOnCompletionWithException")
    pending("testOnCompletionWithExceptionDownstream")
    pending("testMultipleOnCompletions")
    pending("testExceptionFromOnCompletion")
    pending("testContextPreservation")
    it("testEmitExample", function ()
        local completed = false
        flow.from({ 1 }):on_completion(function (err)
            completed = true
        end):to_list()
        assert.is_true(completed)
    end)

    -- defer: cancellation/error semantics.
    pending("testCrashedEmit")
    pending("testCancelledEmit")
    pending("testFailedEmit")
    pending("testFirst")
    pending("testSingle")
    pending("testEmptySingleInterference")
    pending("testTransparencyViolation")
    pending("testTakeOnCompletion")
    pending("testCancelledEmitAllFlow")
    pending("testCancelledEmitAllChannel")
    pending("testOnCompletionBetweenLimitingOperators")
    pending("testEmittingElementsAfterCancellation")
end)
