-- Port of kotlinx.coroutines' BufferTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/BufferTest.kt@1.11.0
describe("BufferTest", function ()
    it("testBuffer", function ()
        local r = flow.from({ 1, 2, 3 }):buffer(2):to_list()
        assert.is_equal(3, #r)
        assert.is_equal(1, r[1])
        assert.is_equal(3, r[3])
    end)

    it("testBufferRendezvous", function ()
        local r = flow.from({ 1, 2, 3 }):buffer(0):to_list()
        assert.is_equal(3, #r)
    end)

    -- defer: dispatcher/fusion/cancellation semantics.
    pending("testBaseline")
    pending("testBufferBufferDefaultFused")
    pending("testBufferDefault")
    pending("testBufferDefaultBufferFused")
    pending("testBufferDefaultTwiceFused")
    pending("testBufferFlowOnDispatcherFused")
    pending("testBufferFlowOnMultipleFused")
    pending("testBufferFlowOnNameFused")
    pending("testCancellation")
    pending("testFailsOnIllegalArguments")
    pending("testFlowOnDispatcherBufferDefault")
    pending("testFlowOnDispatcherBufferFused")
    pending("testFlowOnNameBufferFused")
    pending("testFlowOnNameNoBuffer")
    pending("testBuffer1")
    pending("testBuffer2")
    pending("testBuffer3")
    pending("testBuffer00Fused")
    pending("testBuffer01Fused")
    pending("testBuffer11Fused")
    pending("testBuffer111Fused")
    pending("testBuffer123Fused")
end)