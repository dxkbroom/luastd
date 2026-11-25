-- Port of kotlinx.coroutines' FirstTest.
-- luastd.flow is a pure-Lua cold flow; cancellation semantics differ (no
-- dispatcher), so the cancellation cases are deferred.

local flow = require("luastd.flow")
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

local function scoped_source(cancelled, latch_slot)
    return flow.new(function (emit)
        local latch = async.channel(0)
        latch_slot.value = latch
        async.scope(function (scope)
            local child = scope:launch(function ()
                latch:send(true)
                async.delay(math.huge)
            end)
            child:on_cancel(function () cancelled.value = true end)
            emit(1)
            emit(2)
        end)
    end)
end

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

    -- adapted: use a structured child cancellation hook to verify that first's
    -- BREAK short-circuit stops the upstream scope after selecting one value.
    it(
        "testFirstCancellation",
        runtest(function ()
            local cancelled = { value = false }
            local latch_slot = {}
            local source = scoped_source(cancelled, latch_slot)
            local result = source:first(function ()
                latch_slot.value:receive()
                return true
            end)
            assert.is_equal(1, result)
            assert.is_true(cancelled.value)
        end)
    )

    it(
        "testEmptyFlow",
        runtest(function ()
            local ok, err = pcall(function () flow.empty():first() end)
            assert.is_false(ok)
        end)
    )

    -- adapted: verify reducer predicate failure identity and upstream child
    -- cleanup, then collect again to confirm the cold source restarts.
    it(
        "testErrorCancelsUpstream",
        runtest(function ()
            local cancelled = { value = false }
            local latch_slot = {}
            local source = scoped_source(cancelled, latch_slot)
            local failure = luastd_test.TestException()
            local ok, err = pcall(function ()
                source:first(function ()
                    latch_slot.value:receive()
                    error(failure, 0)
                end)
            end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
            assert.is_true(cancelled.value)
            assert.is_equal(1, source:first())
        end)
    )

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

    -- adapted: first_or_null uses the same short-circuit; verify its value and
    -- upstream child cleanup with the scheduler's cancellation hook.
    it(
        "testFirstOrNullCancellation",
        runtest(function ()
            local cancelled = { value = false }
            local latch_slot = {}
            local source = scoped_source(cancelled, latch_slot)
            local result = source:first_or_null(function ()
                latch_slot.value:receive()
                return true
            end)
            assert.is_equal(1, result)
            assert.is_true(cancelled.value)
        end)
    )

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

    -- adapted: verify first_or_null propagates the predicate error unchanged,
    -- cancels the upstream child, and permits a later cold collection.
    it(
        "testFirstOrNullWhenErrorCancelsUpstream",
        runtest(function ()
            local cancelled = { value = false }
            local latch_slot = {}
            local source = scoped_source(cancelled, latch_slot)
            local failure = luastd_test.TestException()
            local ok, err = pcall(function ()
                source:first_or_null(function ()
                    latch_slot.value:receive()
                    error(failure, 0)
                end)
            end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
            assert.is_true(cancelled.value)
            assert.is_equal(1, source:first_or_null())
        end)
    )

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

    -- defer: the private BREAK sentinel is not exposed as the internal
    -- AbortFlowException that this Kotlin case catches as cancellation.
    pending("testAbortFlowException")

    -- defer: ADR 0005 makes cancellation uncatchable by Lua pcall, so the
    -- Kotlin test's cancellation-finalizer flow cannot continue as written.
    pending("testFirstThrowOnCancellation")
end)
