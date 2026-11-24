-- Port of kotlinx.coroutines' BooleanTerminationTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/BooleanTerminationTest.kt@1.11.0
describe("BooleanTerminationTest", function ()
    it("testAllNominal", function ()
        assert.is_true(flow.from({ 2, 4, 6 }):all(function (x) return x % 2 == 0 end))
        assert.is_false(flow.from({ 2, 3, 4 }):all(function (x) return x % 2 == 0 end))
    end)

    it("testAnyNominal", function ()
        assert.is_true(flow.from({ 1, 2, 3 }):any(function (x) return x == 2 end))
        assert.is_false(flow.from({ 1, 3, 5 }):any(function (x) return x == 2 end))
    end)

    it("testNoneNominal", function ()
        assert.is_true(flow.from({ 1, 3, 5 }):none(function (x) return x == 2 end))
        assert.is_false(flow.from({ 1, 2, 3 }):none(function (x) return x == 2 end))
    end)

    it("testAllEmpty", function ()
        assert.is_true(flow.empty():all(function () return false end))
    end)

    it("testAnyEmpty", function ()
        assert.is_false(flow.empty():any(function () return true end))
    end)

    it("testNoneEmpty", function ()
        assert.is_true(flow.empty():none(function () return true end))
    end)

    -- defer: infinite/cancellation/short-circuit semantics.
    pending("testAllInfinite")
    pending("testAllShortCircuit")
    pending("testAnyInfinite")
    pending("testAnyShortCircuit")
    pending("testNoneInfinite")
    pending("testNoneShortCircuit")
end)