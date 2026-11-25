-- Port of kotlinx.coroutines' DistinctUntilChangedTest.
local async = require("luastd.async")
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

local function total(source)
    return source:fold(0, function (acc, value) return acc + value.i end)
end

local function failing_source(t, values)
    return flow.new(function (emit)
        async.scope(function (scope)
            local child = scope:launch(function () async.delay(math.huge) end)
            child:on_cancel(function () t:expect(3) end)
            t:expect(2)
            async.yield()
            for _, value in ipairs(values) do emit(value) end
            t:expect_unreached()
        end)
    end)
end

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/DistinctUntilChangedTest.kt@1.11.0
describe("DistinctUntilChangedTest", function ()
    it("testDistinctUntilChanged", runtest(function ()
        local values = flow.from({ 1, 1, 2, 2, 1 }):distinct_until_changed():to_list()
        assert.same({ 1, 2, 1 }, values)
    end))

    it("testDistinctUntilChangedKeySelector", runtest(function ()
        local items = { { i = 1 }, { i = 1 }, { i = 2 }, { i = 1 } }
        local source = flow.from(items)
        assert.is_equal(5, total(source:distinct_until_changed()))
        assert.is_equal(4, total(source:distinct_until_changed(function (item) return item.i end)))
    end))

    it("testDistinctUntilChangedAreEquivalent", runtest(function ()
        local items = { { i = 1 }, { i = 1 }, { i = 2 }, { i = 1 } }
        local source = flow.from(items)
        local same_i = function (old, new) return old.i == new.i end
        assert.is_equal(5, total(source:distinct_until_changed()))
        assert.is_equal(4, total(source:distinct_until_changed(nil, same_i)))
    end))

    it("testDistinctUntilChangedAreEquivalentSingleValue", runtest(function ()
        local values = flow.of_one(1):distinct_until_changed(nil, function ()
            error("comparison must not run", 0)
        end):to_list()
        assert.same({ 1 }, values)
    end))

    -- adapted: use async.scope and a child cancellation hook to observe upstream
    -- cleanup when the key selector raises.
    it("testThrowingKeySelector", runtest(function (t)
        local failure = luastd_test.TestException()
        local source = failing_source(t, { { i = 1 } }):distinct_until_changed(function ()
            error(failure, 0)
        end)
        t:expect(1)
        local ok, err = pcall(function () source:to_list() end)
        assert.is_false(ok)
        assert.is_true(rawequal(failure, err))
        t:finish(4)
    end))

    -- adapted: use async.scope and a child cancellation hook to observe upstream
    -- cleanup when the equality callback raises on the second value.
    it("testThrowingAreEquivalent", runtest(function (t)
        local failure = luastd_test.TestException()
        local source = failing_source(t, { { i = 1 }, { i = 2 } }):distinct_until_changed(nil, function ()
            error(failure, 0)
        end)
        t:expect(1)
        local ok, err = pcall(function () source:to_list() end)
        assert.is_false(ok)
        assert.is_true(rawequal(failure, err))
        t:finish(4)
    end))

    -- adapted: collect into a table with a nil sentinel because Lua sequences
    -- cannot retain nil; the operator itself receives actual nil values.
    it("testDistinctUntilChangedNull", runtest(function ()
        local source = flow.new(function (emit)
            emit(nil)
            emit(1)
            emit(nil)
            emit(nil)
        end)
        local nil_value = {}
        local values = {}
        source:distinct_until_changed():collect(function (value)
            table.insert(values, value == nil and nil_value or value)
        end)
        assert.same({ nil_value, 1, nil_value }, values)
    end))

    it("testRepeatedDistinctFusionDefault", runtest(function ()
        local source = flow.from({ 1, 2, 3 })
        local first = source:distinct_until_changed()
        assert.is_false(rawequal(source, first))
        assert.is_true(rawequal(first, first:distinct_until_changed()))
    end))

    it("testRepeatedDistinctFusionAreEquivalent", runtest(function ()
        local source = flow.from({ 1, 2, 3 })
        local same = function (old, new) return old == new end
        local first = source:distinct_until_changed(nil, same)
        assert.is_false(rawequal(source, first))
        assert.is_true(rawequal(first, first:distinct_until_changed(nil, same)))
    end))

    it("testRepeatedDistinctFusionByKey", runtest(function ()
        local source = flow.from({ 1, 2, 3 })
        local key = function (value) return value % 2 end
        local first = source:distinct_until_changed(key)
        assert.is_false(rawequal(source, first))
        assert.is_true(rawequal(first, first:distinct_until_changed(key)))
    end))
end)
