-- Port of kotlinx.coroutines' DebounceTest.
-- Debounce is implemented via channel debounce; timing/virtual-time cases deferred.
---@diagnostic disable: await-in-sync
local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/DebounceTest.kt@1.11.0
describe("DebounceTest", function ()
    it("testEmpty", function ()
        local r = flow.empty():debounce(10):to_list()
        assert.is_equal(0, #r)
    end)

    -- defer: timing/virtual-time based cases.
    pending("testBasic")
    pending("testBasicWithNulls")
    pending("testDebounceDurationSelectorBasic")
    pending("testDebounceSelectorBasic")
    pending("testDownstreamError")
    pending("testDownstreamErrorIsolatedContext")
    pending("testDurationBasic")
    pending("testFailsWithIllegalArgument")
    pending("testPace")
    pending("testScalar")
    pending("testSingleNull")
    pending("testUpstreamError")
    pending("testUpstreamErrorCancellation")
    pending("testUpstreamErrorDebounceNotTriggered")
    pending("testUpstreamErrorDebounceNotTriggeredInIsolatedContext")
    pending("testUpstreamErrorIsolatedContext")
    pending("testZeroDebounceTime")
    pending("testZeroDebounceTimeSelector")
end)
