-- Port of kotlinx.coroutines' DropTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/DropTest.kt@1.11.0
describe("DropTest", function ()
    it("testDrop", function ()
        local r = flow.from({ 1, 2, 3, 4 }):drop(2):to_list()
        assert.is_equal(2, #r)
        assert.is_equal(3, r[1])
        assert.is_equal(4, r[2])
    end)

    it("testEmptyFlow", function ()
        local r = flow.empty():drop(2):to_list()
        assert.is_equal(0, #r)
    end)

    -- defer: error propagation semantics.
    pending("testNegativeCount")
    pending("testErrorCancelsUpstream")

    -- not-applicable: negative count handling differs.
end)
