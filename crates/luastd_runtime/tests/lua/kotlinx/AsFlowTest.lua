-- Port of kotlinx.coroutines' AsFlowTest.
-- asFlow extensions (ranges/sequences/arrays) are not-applicable; luastd uses flow.from.
---@diagnostic disable: await-in-sync
local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/AsFlowTest.kt@1.11.0
describe("AsFlowTest", function ()
    it("testAsFlow", function ()
        local r = flow.from({ 0, 1, 2, 3 }):to_list()
        assert.is_equal(4, #r)
    end)

    -- not-applicable: asFlow on a SharedFlow (SharedFlow is already a Flow).
    pending("testAsFlowIsNotSharedFlow")
end)
