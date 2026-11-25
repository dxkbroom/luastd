-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/FlatMapConcatTest.kt@1.11.0
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

describe("FlatMapConcatTest", function ()
    -- defer: this case uses a hanging inner flow and scheduler yields to verify
    -- only one inner collection starts before cancellation.
    pending("testFlatMapConcurrency")

    it("testFlatMap", runtest(function ()
        local values = {}
        for i = 1, 100 do values[i] = i end
        local result = flow.from(values):flat_map_concat(function (value)
            local inner = {}
            for i = 1, value do inner[i] = i end
            return flow.from(inner)
        end):to_list()
        assert.is_equal(5050, #result)
        local sum = 0
        for _, value in ipairs(result) do sum = sum + value end
        assert.is_equal(171700, sum)
        assert.is_equal(1, result[1])
        assert.is_equal(100, result[#result])
    end))

    it("testSingle", runtest(function ()
        local values = {}
        for i = 0, 99 do values[#values + 1] = i end
        local result = flow.from(values):flat_map_concat(function (value)
            if value == 99 then return flow.of_one(42) end
            return flow.empty()
        end):single()
        assert.is_equal(42, result)
    end))

    -- adapted: Lua arrays cannot represent embedded nils reliably; collect and
    -- assert each emission position directly, including nil values.
    it("testNulls", runtest(function ()
        local source = flow.new(function (emit)
            emit(1)
            emit(nil)
            emit(2)
        end)
        local count = 0
        source:flat_map_concat(function ()
            return flow.new(function (emit)
                emit(1)
                emit(nil)
                emit(nil)
                emit(2)
            end)
        end):collect(function (value)
            count = count + 1
            local position = (count - 1) % 4
            if position == 0 then
                assert.is_equal(1, value)
            elseif position == 3 then
                assert.is_equal(2, value)
            else
                assert.is_nil(value)
            end
        end)
        assert.is_equal(12, count)
    end))

    -- defer: dispatcher-name scheduling and upstream/downstream context capture
    -- cannot be represented by the current flow context model.
    pending("testContext")

    -- defer: this checks nested dispatcher isolation across three flowOn
    -- boundaries; luastd has no NamedDispatcher implementation.
    pending("testIsolatedContext")
end)
