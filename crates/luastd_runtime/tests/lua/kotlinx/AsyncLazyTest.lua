-- kotlin: kotlinx-coroutines-core/common/test/AsyncLazyTest.kt@1.11.0
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("AsyncLazyTest", function ()
    it(
        "testSimple",
        runtest(function (t)
            t:expect(1)
            local d = async.async_lazy(function ()
                t:expect(3)
                return 42
            end)
            t:expect(2)
            assert.is_false(d:is_active())
            assert.is_false(d:is_completed())
            assert.is_equal(42, async.await(d))
            assert.is_false(d:is_active())
            assert.is_true(d:is_completed())
            assert.is_false(d:is_cancelled())
            t:expect(4)
            assert.is_equal(42, async.await(d)) -- second await -- same result
            t:finish(5)
        end)
    )

    it(
        "testLazyDeferAndYield",
        runtest(function (t)
            t:expect(1)
            local d = async.async_lazy(function ()
                t:expect(3)
                async.yield() -- no effect because the parent is waiting
                t:expect(4)
                return 42
            end)
            t:expect(2)
            assert.is_false(d:is_active())
            assert.is_false(d:is_completed())
            assert.is_equal(42, async.await(d))
            assert.is_false(d:is_active())
            assert.is_true(d:is_completed())
            assert.is_false(d:is_cancelled())
            t:expect(5)
            assert.is_equal(42, async.await(d)) -- second await -- same result
            t:finish(6)
        end)
    )

    -- todo: port this Kotlin test in Lua.
    pending("testLazyDeferAndYield2")

    -- todo: port this Kotlin test in Lua.
    pending("testSimpleException")

    -- todo: port this Kotlin test in Lua.
    pending("testLazyDeferAndYieldException")

    -- todo: port this Kotlin test in Lua.
    pending("testCatchException")

    it(
        "testStart",
        runtest(function (t)
            t:expect(1)
            local d = async.async_lazy(function ()
                t:expect(4)
                return 42
            end)
            t:expect(2)
            assert.is_false(d:is_active())
            assert.is_false(d:is_completed())
            assert.is_true(d:start())
            assert.is_true(d:is_active())
            assert.is_false(d:is_completed())
            t:expect(3)
            assert.is_false(d:start())
            async.yield() -- yield to started coroutine
            assert.is_false(d:is_active())
            assert.is_true(d:is_completed())
            assert.is_false(d:is_cancelled())
            t:expect(5)
            assert.is_equal(42, async.await(d)) -- await sees result
            t:finish(6)
        end)
    )

    -- todo: port this Kotlin test in Lua.
    pending("testCancelBeforeStart")

    -- todo: port this Kotlin test in Lua.
    pending("testCancelWhileComputing")
end)
