-- Port of kotlinx.coroutines' ChunkedTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/ChunkedTest.kt@1.11.0
describe("ChunkedTest", function ()
    it("testChunked", function ()
        local r = flow.from({ 1, 2, 3, 4, 5 }):chunked(2):to_list()
        assert.is_equal(3, #r)
        assert.is_equal(2, #r[1])
        assert.is_equal(5, r[3][1])
    end)

    it("testEmpty", function ()
        local r = flow.empty():chunked(2):to_list()
        assert.is_equal(0, #r)
    end)

    pending("testChunkedCancelled")
    pending("testChunkedCancelledWithSuspension")
    pending("testChunkedDoesNotIgnoreCancellation")
    it("testIae", function ()
        local ok = pcall(function () flow.from({ 1, 2 }):chunked(0) end)
        assert.is_false(ok)
    end)

    -- defer: cancellation semantics.
    pending("testSample")
end)
