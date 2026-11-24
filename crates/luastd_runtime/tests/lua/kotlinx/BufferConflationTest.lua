-- Port of kotlinx.coroutines' BufferConflationTest.
-- conflate is a no-op in the synchronous model.
---@diagnostic disable: await-in-sync
local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/BufferConflationTest.kt@1.11.0
describe("BufferConflationTest", function ()
    it("testConflate", function ()
        local r = flow.from({ 1, 2, 3 }):conflate():to_list()
        assert.is_equal(3, #r)
    end)

    -- defer: dispatcher/conflation semantics.
    pending("testBufferConflated")
    pending("testBufferDropOldest")
    pending("testBuffer0DropOldest")
    pending("testBuffer1DropOldest")
    pending("testBuffer10DropOldest")
    pending("testConflateOverridesBuffer")
    pending("testDoubleConflate")
    pending("testConflateBuffer10Combine")
    pending("testBufferDropLatest")
    pending("testBuffer0DropLatest")
    pending("testBuffer1DropLatest")
    pending("testBufferDropLatestOverrideBuffer")
    pending("testBufferDropLatestOverrideConflate")
    pending("testBufferDropLatestBuffer7Combine")
    pending("testConflateOverrideBufferDropLatest")
    pending("testBuffer3DropOldestOverrideBuffer8DropLatest")
end)
