-- Port of kotlinx.coroutines' BooleanTerminationTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/BooleanTerminationTest.kt@1.11.0
describe("BooleanTerminationTest", function ()
    it("testAnyNominal", function ()
        assert.is_true(flow.from({ 1, 2, 3 }):any(function (x) return x == 2 end))
        assert.is_false(flow.from({ 1, 3, 5 }):any(function (x) return x == 2 end))
    end)

    it("testAnyEmpty", function ()
        assert.is_false(flow.empty():any(function () return true end))
    end)

    it("testAnyInfinite", function ()
        assert.is_true(flow.new(function (emit)
                while true do
                    emit(5)
                end
            end):any(function (x) return x == 5 end))
    end)
    it(
        "testAnyShortCircuit",
        runtest(function (t)
            assert.is_true(flow.new(function (emit)
                    emit(1)
                    emit(2)
                    t:expect_unreached()
                end):any(function (x) return x == 2 end))
        end)
    )
    it("testAllNominal", function ()
        assert.is_true(flow.from({ 2, 4, 6 }):all(function (x) return x % 2 == 0 end))
        assert.is_false(flow.from({ 2, 3, 4 }):all(function (x) return x % 2 == 0 end))
    end)

    it("testAllEmpty", function ()
        assert.is_true(flow.empty():all(function () return false end))
    end)

    it("testAllInfinite", function ()
        assert.is_false(flow.new(function (emit)
                while true do
                    emit(5)
                end
            end):all(function (x) return x == 0 end))
    end)
    it(
        "testAllShortCircuit",
        runtest(function (t)
            assert.is_false(flow.new(function (emit)
                    emit(1)
                    emit(2)
                    t:expect_unreached()
                end):all(function (x) return x <= 1 end))
        end)
    )
    it("testNoneNominal", function ()
        assert.is_true(flow.from({ 1, 3, 5 }):none(function (x) return x == 2 end))
        assert.is_false(flow.from({ 1, 2, 3 }):none(function (x) return x == 2 end))
    end)

    it("testNoneEmpty", function ()
        assert.is_true(flow.empty():none(function () return true end))
    end)

    it("testNoneInfinite", function ()
        assert.is_false(flow.new(function (emit)
                while true do
                    emit(5)
                end
            end):none(function (x) return x == 5 end))
    end)
    it(
        "testNoneShortCircuit",
        runtest(function (t)
            assert.is_false(flow.new(function (emit)
                    emit(1)
                    emit(2)
                    t:expect_unreached()
                end):none(function (x) return x == 2 end))
        end)
    )
end)
