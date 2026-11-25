-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/CombineParametersTest.kt@1.11.0
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest
local nil_value = {}
local unpack_values = table.unpack or unpack

local function encode_nil(source)
    return source:map(function (value)
        if value == nil then return nil_value end
        return value
    end)
end

local function combine_values(sources, transform)
    local combined = encode_nil(sources[1]):map(function (value) return { value } end)
    for index = 2, #sources do
        combined = combined:combine(encode_nil(sources[index]), function (values, value)
            local next_values = {}
            for i = 1, #values do
                next_values[i] = values[i]
            end
            next_values[#next_values + 1] = value
            return next_values
        end)
    end
    return combined:map(function (values)
        local count = #values
        for i, value in ipairs(values) do
            if rawequal(value, nil_value) then values[i] = nil end
        end
        return transform(unpack_values(values, 1, count))
    end)
end

describe("CombineParametersTest", function ()
    -- adapted: fixed-arity combine is composed from binary Flow:combine calls;
    -- a private marker carries Kotlin's null input through Lua flows.
    it(
        "testThreeParameters",
        runtest(function ()
            local result = combine_values({ flow.of_one("1"), flow.of_one(2), flow.of_one(nil) }, function (a, b, c)
                return a .. b .. tostring(c)
            end):single()
            assert.is_equal("12nil", result)
        end)
    )

    -- adapted: combineTransform is absent, so the binary composition returns
    -- the one value this Kotlin transform emits.
    it(
        "testThreeParametersTransform",
        runtest(function ()
            local result = combine_values({ flow.of_one("1"), flow.of_one(2), flow.of_one(nil) }, function (a, b, c)
                return a .. b .. tostring(c)
            end):single()
            assert.is_equal("12nil", result)
        end)
    )

    -- adapted: compose two-input combine calls; no four-input overload exists.
    it(
        "testFourParameters",
        runtest(function ()
            local result = combine_values(
                { flow.of_one("1"), flow.of_one(2), flow.of_one("3"), flow.of_one(nil) },
                function (a, b, c, d)
                    return a .. b .. c .. tostring(d)
                end
            ):single()
            assert.is_equal("123nil", result)
        end)
    )

    -- adapted: combineTransform is absent, so the composed transform returns
    -- the single value emitted by its Kotlin counterpart.
    it(
        "testFourParametersTransform",
        runtest(function ()
            local result = combine_values(
                { flow.of_one("1"), flow.of_one(2), flow.of_one("3"), flow.of_one(nil) },
                function (a, b, c, d)
                    return a .. b .. c .. tostring(d)
                end
            ):single()
            assert.is_equal("123nil", result)
        end)
    )

    -- adapted: compose two-input combine calls; no five-input overload exists.
    it(
        "testFiveParameters",
        runtest(function ()
            local result = combine_values(
                { flow.of_one("1"), flow.of_one(2), flow.of_one("3"), flow.of_one(4), flow.of_one(nil) },
                function (a, b, c, d, e)
                    return a .. b .. c .. d .. tostring(e)
                end
            ):single()
            assert.is_equal("1234nil", result)
        end)
    )

    -- adapted: combineTransform is absent, so the composed transform returns
    -- the single value emitted by its Kotlin counterpart.
    it(
        "testFiveParametersTransform",
        runtest(function ()
            local result = combine_values(
                { flow.of_one("1"), flow.of_one(2), flow.of_one("3"), flow.of_one(4), flow.of_one(nil) },
                function (a, b, c, d, e)
                    return a .. b .. c .. d .. tostring(e)
                end
            ):single()
            assert.is_equal("1234nil", result)
        end)
    )

    it(
        "testNonMatchingTypes",
        runtest(function ()
            local result = flow.of_one(1):combine(flow.of_one("2"), function (a, b)
                return tostring(a) .. tostring(b)
            end):single()
            assert.is_equal("12", result)
        end)
    )

    -- adapted: compose binary Flow:combine over the Kotlin input list while
    -- preserving each source's distinct value type.
    it(
        "testNonMatchingTypesIterable",
        runtest(function ()
            local result = combine_values({ flow.of_one(1), flow.of_one("2") }, function (a, b)
                return tostring(a) .. tostring(b)
            end):single()
            assert.is_equal("12", result)
        end)
    )

    -- not-applicable: the vararg combine and combineTransform overloads are
    -- absent; the runtime API provides binary Flow:combine instead.
    pending("testVararg")
    pending("testVarargTransform")
    pending("testSingleVararg")
    pending("testSingleVarargTransform")

    -- not-applicable: Lua has no reified array type, and the combine overload
    -- producing Kotlin's typed Array is not exposed.
    pending("testReified")
    pending("testReifiedTransform")

    -- not-applicable: combineTransform and iterable/vararg overloads are not
    -- present, including their empty-input behavior.
    pending("testTransformEmptyIterable")
    pending("testTransformEmptyVararg")
    pending("testEmptyIterable")
    pending("testEmptyVararg")

    -- adapted: compose binary combine calls over the same source shapes;
    -- assert every result is a complete tuple and all sources make progress
    -- to their latest value despite the different pairwise scheduling.
    it(
        "testFairnessInVariousConfigurations",
        runtest(function ()
            for flows_count = 2, 5 do
                for flow_size = 1, 5 do
                    local sources = {}
                    for _ = 1, flows_count do
                        local values = {}
                        for value = 1, flow_size do
                            values[#values + 1] = value
                        end
                        sources[#sources + 1] = flow.from(values)
                    end
                    local result = combine_values(sources, function (...)
                        local values = { ... }
                        local parts = {}
                        for i, value in ipairs(values) do
                            parts[i] = tostring(value)
                        end
                        return table.concat(parts)
                    end):to_list()
                    assert.is_true(#result > 0)
                    for _, value in ipairs(result) do
                        assert.is_equal(flows_count, #value)
                        for i = 1, #value do
                            local digit = tonumber(value:sub(i, i))
                            assert.is_true(digit >= 1 and digit <= flow_size)
                        end
                    end
                    assert.is_equal(tostring(flow_size):rep(flows_count), result[#result])
                end
            end
        end)
    )

    -- adapted: the Lua implementation uses a bounded event channel and latest
    -- values, not Kotlin's epoch batches; stress the event path and verify the
    -- final value reflects the latest element from both sources.
    it(
        "testEpochOverflow",
        runtest(function ()
            local values = {}
            for i = 0, 1023 do
                values[#values + 1] = i
            end
            local source = flow.from(values)
            local result = source:combine(source, function (a, b) return a + b end):to_list()
            assert.is_true(#result > 0)
            for _, value in ipairs(result) do
                assert.is_true(value >= 0 and value <= 2046)
            end
            assert.is_equal(2046, result[#result])
        end)
    )

    -- not-applicable: the overload returns a typed Kotlin Array, which has no
    -- corresponding runtime-visible representation in Lua.
    pending("testArrayType")
end)
