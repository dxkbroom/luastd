-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/LastTest.kt@1.11.0
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

describe("LastTest", function ()
    -- adapted: the tested last value is supported; luastd has no last_or_null
    -- terminal operation, so only assert the available result.
    it("testLast", runtest(function ()
        assert.is_equal(3, flow.from({ 1, 2, 3 }):last())
    end))

    -- adapted: flow.new can emit nil and last preserves it; last_or_null is
    -- absent, so check only the existing last operation.
    it("testNulls", runtest(function ()
        local result = flow.new(function (emit)
            emit(1)
            emit(nil)
        end):last()
        assert.is_nil(result)
    end))

    -- adapted: verify a prior nil does not replace the final non-nil value;
    -- the separate last_or_null API is not exposed.
    it("testNullsLastOrNull", runtest(function ()
        local result = flow.new(function (emit)
            emit(nil)
            emit(1)
        end):last()
        assert.is_equal(1, result)
    end))

    -- adapted: assert last raises for an empty flow; luastd has no
    -- last_or_null operation to assert its nil result.
    it("testEmptyFlow", runtest(function ()
        local ok, err = pcall(function () flow.empty():last() end)
        assert.is_false(ok)
        assert.is_true(err:find("NoSuchElementException", 1, true) ~= nil)
    end))

    -- adapted: Lua tables with raising equality/string conversion metamethods
    -- stand in for BadClass; rawequal verifies last returns the same object.
    it("testBadClass", runtest(function ()
        local bad = setmetatable({}, {
            __eq = function () error("equals") end,
            __tostring = function () error("toString") end
        })
        local result = flow.from({ bad }):last()
        assert.is_true(rawequal(bad, result))
    end))
end)
