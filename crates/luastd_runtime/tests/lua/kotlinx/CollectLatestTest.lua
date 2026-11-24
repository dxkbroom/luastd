-- Port of kotlinx.coroutines' CollectLatestTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/CollectLatestTest.kt@1.11.0
describe("CollectLatestTest", function ()
    it("testNoSuspension", function ()
        local acc = {}
        flow.from({ 1, 2, 3 }):collect_latest(function (v) table.insert(acc, v) end)
        assert.is_equal(3, #acc)
    end)

    -- defer: suspension/cancellation semantics.
    pending("testSuspension")
    pending("testUpstreamErrorSuspension")
    pending("testDownstreamError")
end)
