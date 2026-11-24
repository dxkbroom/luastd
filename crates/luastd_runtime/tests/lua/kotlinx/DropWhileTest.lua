-- Port of kotlinx.coroutines' DropWhileTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/DropWhileTest.kt@1.11.0
describe("DropWhileTest", function ()
    it("testDropWhile", function ()
        local r = flow.from({ 1, 2, 3, 4 }):drop_while(function (x) return x < 3 end):to_list()
        assert.is_equal(2, #r)
        assert.is_equal(3, r[1])
        assert.is_equal(4, r[2])
    end)

    it("testEmptyFlow", function ()
        local r = flow.empty():drop_while(function (x) return true end):to_list()
        assert.is_equal(0, #r)
    end)

    -- defer: error propagation semantics.
    pending("testErrorCancelsUpstream")
end)