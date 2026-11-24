-- Port of kotlinx.coroutines' DistinctUntilChangedTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/DistinctUntilChangedTest.kt@1.11.0
describe("DistinctUntilChangedTest", function ()
    it("testDistinctUntilChanged", function ()
        local r = flow.from({ 1, 1, 2, 2, 3 }):distinct_until_changed():to_list()
        assert.is_equal(3, #r)
        assert.is_equal(1, r[1])
        assert.is_equal(2, r[2])
        assert.is_equal(3, r[3])
    end)

    it("testDistinctUntilChangedKeySelector", function ()
        local items = { { id = 1 }, { id = 1 }, { id = 2 } }
        local r = flow.from(items):distinct_until_changed(function (x) return x.id end):to_list()
        assert.is_equal(2, #r)
    end)

    -- defer: equality/key edge cases.
    pending("testDistinctUntilChangedAreEquivalent")
    pending("testDistinctUntilChangedAreEquivalentSingleValue")
    pending("testThrowingKeySelector")
    pending("testThrowingAreEquivalent")
    pending("testDistinctUntilChangedNull")
    pending("testRepeatedDistinctFusionDefault")
    pending("testRepeatedDistinctFusionAreEquivalent")
    pending("testRepeatedDistinctFusionByKey")
end)
