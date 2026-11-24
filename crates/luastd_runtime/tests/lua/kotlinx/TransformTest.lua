-- Port of kotlinx.coroutines' TransformTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/TransformTest.kt@1.11.0
describe("TransformTest", function ()
    it("testDoubleEmit", function ()
        local r = flow.from({ 1, 2, 3 }):transform(function (emit, v)
            emit(v)
            emit(v)
        end):to_list()
        assert.is_equal(6, #r)
        assert.is_equal(1, r[1])
        assert.is_equal(1, r[2])
        assert.is_equal(2, r[3])
    end)
end)
