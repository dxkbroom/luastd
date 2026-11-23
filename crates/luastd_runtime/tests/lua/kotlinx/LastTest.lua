-- Port of kotlinx.coroutines' LastTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/LastTest.kt@1.11.0
describe("LastTest", function ()
    it("testLast", function ()
        assert.is_equal(3, flow.from({ 1, 2, 3 }):last())
    end)

    it("testEmptyFlow", function ()
        local ok = pcall(function () flow.empty():last() end)
        assert.is_false(ok)
    end)

    -- defer: lastOrNull not implemented.
    pending("testNulls")
    pending("testNullsLastOrNull")
    pending("testBadClass")
end)