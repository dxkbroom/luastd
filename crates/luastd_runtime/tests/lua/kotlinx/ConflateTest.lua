-- Port of kotlinx.coroutines' ConflateTest.
-- conflate is a no-op in the synchronous model.
---@diagnostic disable: await-in-sync
local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/ConflateTest.kt@1.11.0
describe("ConflateTest", function ()
    it("testExample", function ()
        local r = flow.from({ 1, 2, 3 }):conflate():to_list()
        assert.is_equal(3, #r)
    end)
end)