-- Port of kotlinx.coroutines' OnEachTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/OnEachTest.kt@1.11.0
describe("OnEachTest", function ()
    it("testOnEach", function ()
        local seen = {}
        local r = flow.from({ 1, 2, 3 }):on_each(function (v) table.insert(seen, v) end):to_list()
        assert.is_equal(3, #r)
        assert.is_equal(3, #seen)
        assert.is_equal(2, seen[2])
    end)

    it("testEmptyFlow", function ()
        local r = flow.empty():on_each(function () end):to_list()
        assert.is_equal(0, #r)
    end)

    -- defer: error propagation semantics.
    pending("testErrorCancelsUpstream")
end)