-- Port of kotlinx.coroutines' FirstTest.
-- luastd.flow is a pure-Lua cold flow; cancellation semantics differ (no
-- dispatcher), so the cancellation cases are deferred.

local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/FirstTest.kt@1.11.0
describe("FirstTest", function ()
    it(
        "testFirst",
        runtest(function ()
            local f = flow.from({ 1, 2, 3 })
            assert.is_equal(1, f:first())
        end)
    )

    -- adapted: use a source callback to emit nil because Lua arrays cannot store it.
    it(
        "testNulls",
        runtest(function ()
            local source = flow.new(function (emit)
                    emit(nil)
                    emit(1)
                end)
            assert.is_nil(source:first())
            assert.is_nil(source:first(function (value) return value == nil end))
            assert.is_equal(1, source:first(function (value) return value ~= nil end))
        end)
    )

    it(
        "testFirstWithPredicate",
        runtest(function ()
            local f = flow.from({ 1, 2, 3 })
            assert.is_equal(1, f:first(function (x) return x > 0 end))
            assert.is_equal(2, f:first(function (x) return x > 1 end))
            local ok = pcall(function () f:first(function (x) return x > 3 end) end)
            assert.is_false(ok)
        end)
    )

    -- defer: cancellation-driven upstream cancellation needs scheduler integration.
    pending("testFirstCancellation")

    it(
        "testEmptyFlow",
        runtest(function ()
            local ok, err = pcall(function () flow.empty():first() end)
            assert.is_false(ok)
        end)
    )

    -- defer: upstream cancellation on error requires scope integration.
    pending("testErrorCancelsUpstream")

    it(
        "testFirstOrNull",
        runtest(function ()
            assert.is_equal(1, flow.from({ 1, 2, 3 }):first_or_null())
        end)
    )

    it(
        "testFirstOrNullWithPredicate",
        runtest(function ()
            local f = flow.from({ 1, 2, 3 })
            assert.is_equal(1, f:first_or_null(function (value) return value > 0 end))
            assert.is_equal(2, f:first_or_null(function (value) return value > 1 end))
            assert.is_nil(f:first_or_null(function (value) return value > 3 end))
        end)
    )

    -- defer: cancellation-driven upstream cleanup needs scheduler integration.
    pending("testFirstOrNullCancellation")

    it(
        "testFirstOrNullWithEmptyFlow",
        runtest(function ()
            assert.is_nil(flow.empty():first_or_null())
            assert.is_nil(flow.empty():first_or_null(function () return true end))
        end)
    )

    -- adapted: `flow.new` emits the nil value directly; a sentinel collector
    -- confirms it was present because Lua arrays cannot contain nil entries.
    it(
        "testFirstOrNullWithNullElement",
        runtest(function ()
            local nil_value = {}
            local source = flow.new(function (emit)
                    emit(nil)
                    emit("after nil")
                end)
            local collected = {}
            source:collect(function (value)
                collected[#collected + 1] = value == nil and nil_value or value
            end)
            assert.same({ nil_value, "after nil" }, collected)
            assert.is_nil(source:first_or_null())
            assert.is_nil(source:first_or_null(function (value) return value == nil end))
        end)
    )

    -- defer: predicate failure must cancel a structured upstream scope.
    pending("testFirstOrNullWhenErrorCancelsUpstream")

    -- adapted: a Lua table has identity equality, matching the tested identity
    -- preservation without Kotlin's custom equals/hashCode implementation.
    it(
        "testBadClass",
        runtest(function ()
            local instance = {}
            local source = flow.of_one(instance)
            assert.is_true(rawequal(instance, source:first()))
            assert.is_true(rawequal(instance, source:first_or_null()))
            assert.is_true(rawequal(instance, source:first(function () return true end)))
            assert.is_true(rawequal(instance, source:first_or_null(function () return true end)))
        end)
    )

    -- defer: abort flow exception handling not yet ported.
    pending("testAbortFlowException")

    -- defer: cancellation propagation not yet ported.
    pending("testFirstThrowOnCancellation")
end)
