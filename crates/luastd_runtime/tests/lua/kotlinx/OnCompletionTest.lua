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

    it("testEmitExample", function ()
        local completed = false
        flow.from({ 1 }):on_completion(function (err)
            completed = true
        end):to_list()
        assert.is_true(completed)
    end)

    -- defer: cancellation/error semantics.
    pending("testCancelledEmit")
    pending("testCancelledEmitAllChannel")
    pending("testCancelledEmitAllFlow")
    pending("testContextPreservation")
    pending("testCrashedEmit")
    pending("testEmittingElementsAfterCancellation")
    pending("testEmptySingleInterference")
    pending("testExceptionFromOnCompletion")
    pending("testFailedEmit")
    pending("testFirst")
    pending("testMultipleOnCompletions")
    pending("testOnCompletionBetweenLimitingOperators")
    pending("testOnCompletionWithException")
    pending("testOnCompletionWithExceptionDownstream")
    pending("testSingle")
    pending("testTakeOnCompletion")
    pending("testTransparencyViolation")
end)
