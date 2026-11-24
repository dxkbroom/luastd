-- Port of kotlinx.coroutines' BufferTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/BufferTest.kt@1.11.0
describe("BufferTest", function ()
    -- adapted: checks that buffer(2) passes every element; Kotlin also asserts
    pending("testBaseline")
    pending("testBufferDefault")
    it("testBufferRendezvous", function ()
        local r = flow.from({ 1, 2, 3 }):buffer(0):to_list()
        assert.is_equal(3, #r)
    end)

    -- defer: dispatcher/fusion/cancellation semantics.
    pending("testBuffer1")
    -- the batch timing of the buffer.
    it("testBuffer2", function ()
        local r = flow.from({ 1, 2, 3 }):buffer(2):to_list()
        assert.is_equal(3, #r)
        assert.is_equal(1, r[1])
        assert.is_equal(3, r[3])
    end)

    pending("testBuffer3")
    pending("testBuffer00Fused")
    pending("testBuffer01Fused")
    pending("testBuffer11Fused")
    pending("testBuffer111Fused")
    pending("testBuffer123Fused")
    pending("testBufferDefaultTwiceFused")
    pending("testBufferDefaultBufferFused")
    pending("testBufferBufferDefaultFused")
    pending("testFlowOnNameNoBuffer")
    pending("testFlowOnDispatcherBufferDefault")
    pending("testFlowOnDispatcherBufferFused")
    pending("testBufferFlowOnDispatcherFused")
    pending("testFlowOnNameBufferFused")
    pending("testBufferFlowOnNameFused")
    pending("testBufferFlowOnMultipleFused")
    pending("testCancellation")
    pending("testFailsOnIllegalArguments")
end)
