-- kotlin: kotlinx-coroutines-core/common/test/AsyncLazyTest.kt@1.11.0
---@diagnostic disable: await-in-sync
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

    it(
        "testLazyDeferAndYield2",
        runtest(function (t)
            t:expect(1)
            local d = async.async_lazy(function ()
                t:expect(7)
                return 42
            end)
            t:expect(2)
            assert.is_false(d:is_active())
            assert.is_false(d:is_completed())
            async.launch(function ()
                t:expect(4)
                assert.is_false(d:is_active())
                assert.is_false(d:is_completed())
                async.yield() -- hand control back to main
                t:expect(6)
                assert.is_true(d:is_active())
                assert.is_false(d:is_completed())
                async.yield() -- let the lazy deferred run
            end)
            t:expect(3)
            assert.is_false(d:is_active())
            assert.is_false(d:is_completed())
            async.yield()
            t:expect(5)
            assert.is_false(d:is_active())
            assert.is_false(d:is_completed())
            assert.is_equal(42, async.await(d))
            assert.is_true(d:is_completed())
            t:finish(8)
        end)
    )

    it(
        "testSimpleException",
        runtest({ expected = "TestException" }, function (t)
            t:expect(1)
            local d = async.async_lazy(function ()
                t:finish(3)
                error(luastd_test.TestException())
            end)
            t:expect(2)
            assert.is_false(d:is_active())
            assert.is_false(d:is_completed())
            async.await(d) -- raises TestException
        end)
    )

    it(
        "testLazyDeferAndYieldException",
        runtest({ expected = "TestException" }, function (t)
            t:expect(1)
            local d = async.async_lazy(function ()
                t:expect(3)
                async.yield() -- no effect while the parent is waiting
                t:finish(4)
                error(luastd_test.TestException())
            end)
            t:expect(2)
            assert.is_false(d:is_active())
            assert.is_false(d:is_completed())
            async.await(d) -- raises TestException
        end)
    )

    -- adapted: a supervisor scope isolates the failed child where Kotlin uses
    -- NonCancellable; try_await exposes the failed result without cancelling
    -- the test scope.
    it(
        "testCatchException",
        runtest(function (t)
            t:expect(1)
            async.supervisor_scope(function ()
                local d = async.async_lazy(function ()
                    t:expect(3)
                    error(luastd_test.TestException())
                end)
                t:expect(2)
                assert.is_false(d:is_active())
                assert.is_false(d:is_completed())
                local ok, err = async.try_await(d)
                assert.is_false(ok)
                assert.is_equal("TestException", err.kind)
                assert.is_false(d:is_active())
                assert.is_true(d:is_completed())
                assert.is_true(d:is_cancelled())
                t:expect(4)
            end)
            t:finish(5)
        end)
    )

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

    it(
        "testCancelBeforeStart",
        runtest(function (t)
            t:expect(1)
            local d = async.async_lazy(function ()
                t:expect_unreached()
                return 42
            end)
            t:expect(2)
            assert.is_false(d:is_active())
            assert.is_false(d:is_completed())
            d:cancel()
            assert.is_false(d:is_active())
            assert.is_true(d:is_completed())
            assert.is_true(d:is_cancelled())
            assert.is_false(d:start())
            t:finish(3)
            local ok = async.try_await(d)
            assert.is_false(ok)
        end)
    )

    it(
        "testCancelWhileComputing",
        runtest(function (t)
            t:expect(1)
            local d = async.async_lazy(function ()
                t:expect(4)
                async.yield() -- yield to main, which cancels this job
                t:expect_unreached()
                return 42
            end)
            t:expect(2)
            assert.is_false(d:is_active())
            assert.is_false(d:is_completed())
            assert.is_true(d:start())
            assert.is_true(d:is_active())
            t:expect(3)
            async.yield()
            t:expect(5)
            assert.is_true(d:is_active())
            d:cancel()
            assert.is_false(d:is_active())
            assert.is_true(d:is_cancelled())
            t:finish(6)
            local ok = async.try_await(d)
            assert.is_false(ok)
        end)
    )
end)
