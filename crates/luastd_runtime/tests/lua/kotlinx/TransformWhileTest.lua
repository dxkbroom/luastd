-- Port of kotlinx.coroutines' TransformWhileTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/TransformWhileTest.kt@1.11.0
describe("TransformWhileTest", function ()
    it("testSimple", function ()
        local r = flow.from({ 1, 2, 3 }):transform_while(function (emit, v)
            emit(v)
            return v < 2
        end):to_list()
        assert.is_equal(2, #r)
    end)

    -- defer: cancellation semantics.
    pending("testCancelUpstream")
    it("testExample", function ()
        local r = flow.from({ 1, 2, 3, 4 }):transform_while(function (emit, v)
            if v > 2 then return false end
            emit(v)
            return true
        end):to_list()
        assert.is_equal(2, #r)
        assert.is_equal(1, r[1])
        assert.is_equal(2, r[2])
    end)

end)
