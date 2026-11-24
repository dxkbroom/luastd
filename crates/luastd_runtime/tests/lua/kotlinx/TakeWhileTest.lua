-- Port of kotlinx.coroutines' TakeWhileTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/TakeWhileTest.kt@1.11.0
describe("TakeWhileTest", function ()
    it("testTakeWhile", function ()
        local r = flow.from({ 1, 2, 3, 4 }):take_while(function (x) return x < 3 end):to_list()
        assert.is_equal(2, #r)
        assert.is_equal(1, r[1])
        assert.is_equal(2, r[2])
    end)

    it("testEmptyFlow", function ()
        local r = flow.empty():take_while(function (x) return true end):to_list()
        assert.is_equal(0, #r)
    end)

    -- defer: cancellation/error semantics.
    pending("testCancelUpstream")
    pending("testErrorCancelsUpstream")
end)