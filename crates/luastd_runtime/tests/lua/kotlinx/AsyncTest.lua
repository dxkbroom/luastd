-- Port of kotlinx.coroutines' AsyncTest (see AGENTS.md, "Kotlin test ports").
-- luastd has no `NonCancellable`, standalone `Job()` parents or `start`
-- modes; a `supervisor_scope` stands in for a detached parent where that keeps
-- the point of the test. Awaiting a cancelled deferred raises the catchable
-- `JobCancelled` kind where Kotlin throws `CancellationException`.
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

--- Kotlin's `try { ... } catch (e: ...)`: the error `fn` raised.
---@param fn fun()
---@return any
local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return err
end

-- kotlin: kotlinx-coroutines-core/common/test/AsyncTest.kt@1.11.0
describe("AsyncTest", function ()
    it(
        "testSimple",
        runtest(function (t)
            t:expect(1)
            local d = async.async(function ()
                t:expect(3)
                return 42
            end)
            t:expect(2)
            assert.is_true(d:is_active())
            assert.is_equal(42, async.await(d))
            assert.is_true(not d:is_active())
            t:expect(4)
            assert.is_equal(42, async.await(d)) -- second await -- same result
            t:finish(5)
        end)
    )

    -- defer: no `CoroutineStart.UNDISPATCHED`; `async` always dispatches.
    pending("testUndispatched")

    it(
        "testSimpleException",
        runtest({ expected = "TestException" }, function (t)
            t:expect(1)
            local d = async.async(function ()
                t:finish(3)
                error(luastd_test.TestException())
            end)
            t:expect(2)
            async.await(d) -- will throw TestException
        end)
    )

    -- defer: no `NonCancellable`, `CoroutineStart.ATOMIC` or cancellation causes.
    pending("testCancellationWithCause")

    -- adapted: no standalone `Job()` parent; the deferred lives in a
    -- supervisor scope, where an unawaited failure is not reported either.
    it(
        "testLostException",
        runtest(function (t)
            t:expect(1)
            async.supervisor_scope(function ()
                local deferred = async.async(function ()
                    t:expect(2)
                    error(luastd_test.TestException())
                end)
                -- Exception is not consumed -> nothing is reported
                async.join(deferred)
            end)
            t:finish(3)
        end)
    )

    -- adapted: no `NonCancellable`; the decomposed deferred runs in its own
    -- supervisor scope so its failure stays with it until awaited.
    it(
        "testParallelDecompositionCaughtException",
        runtest(function ()
            local deferred = async.async(function ()
                local decomposed = async.supervisor_scope(function ()
                    return async.async(function () error(luastd_test.TestException()) end)
                end)
                local ok, err = async.try_await(decomposed)
                assert.is_false(ok)
                assert.is_equal("TestException", err.kind)
                return 42
            end)
            assert.is_equal(42, async.await(deferred))
        end)
    )

    -- not-applicable: a `catch` around awaiting a failing child cannot recover its scope
    -- in Kotlin either: the child's failure has already cancelled the parent,
    -- so its 42 is lost and `deferred` still fails. luastd raises that
    -- cancellation at the await instead of entering the catch (ADR 0005); to
    -- recover, run the child in `async.try_scope`.
    pending("testParallelDecompositionCaughtExceptionWithInheritedParent")

    -- adapted: no `NonCancellable`; the deferred is a child of the test's
    -- scope, so the TestException reaches runtest through it either way.
    it(
        "testParallelDecompositionUncaughtExceptionWithInheritedParent",
        runtest({ expected = "TestException" }, function (t)
            local deferred = async.async(function ()
                local decomposed = async.async(function ()
                    error(luastd_test.TestException())
                end)
                return async.await(decomposed)
            end)
            async.await(deferred)
            t:expect_unreached()
        end)
    )

    -- adapted: as testParallelDecompositionUncaughtExceptionWithInheritedParent
    -- (the Kotlin bodies are the same).
    it(
        "testParallelDecompositionUncaughtException",
        runtest({ expected = "TestException" }, function (t)
            local deferred = async.async(function ()
                local decomposed = async.async(function ()
                    error(luastd_test.TestException())
                end)
                return async.await(decomposed)
            end)
            async.await(deferred)
            t:expect_unreached()
        end)
    )

    -- defer: no `NonCancellable` or `CoroutineStart.ATOMIC`.
    pending("testCancellationTransparency")

    it(
        "testDeferAndYieldException",
        runtest({ expected = "TestException" }, function (t)
            t:expect(1)
            local d = async.async(function ()
                t:expect(3)
                async.yield() -- no effect, parent waiting
                t:finish(4)
                error(luastd_test.TestException())
            end)
            t:expect(2)
            async.await(d) -- will throw TestException
        end)
    )

    -- adapted: different order. In Kotlin, `d` completing re-dispatches both
    -- waiters behind the main coroutine (expect 10, then 11 and 12 on the third
    -- yield). luastd's `yield` is tokio's `yield_now`, which lets tasks woken in
    -- the meantime run first: both waiters resume before main gets back.
    it(
        "testDeferWithTwoWaiters",
        runtest(function (t)
            t:expect(1)
            local d = async.async(function ()
                t:expect(5)
                async.yield()
                t:expect(9)
                return 42
            end)
            t:expect(2)
            async.launch(function ()
                t:expect(6)
                assert.is_equal(42, async.await(d))
                t:expect(10) -- Kotlin: 11
            end)
            t:expect(3)
            async.launch(function ()
                t:expect(7)
                assert.is_equal(42, async.await(d))
                t:expect(11) -- Kotlin: 12
            end)
            t:expect(4)
            async.yield() -- this actually yields control to async, which produces results and resumes both waiters (in order)
            t:expect(8)
            async.yield() -- yield again to "d", which completes; the waiters resume right after it
            t:expect(12) -- Kotlin: 10
            async.yield() -- Kotlin: yield to both waiters
            t:finish(13)
        end)
    )

    -- adapted: Kotlin's BadClass throws from equals/hashCode/toString; here a
    -- table whose metamethods raise, compared with rawequal.
    it(
        "testDeferBadClass",
        runtest(function (t)
            local function bad()
                error("BadClass")
            end
            local value = setmetatable({}, { __eq = bad, __tostring = bad, __index = bad, __len = bad })
            local d = async.async(function ()
                t:expect(1)
                return value
            end)
            assert.is_true(rawequal(async.await(d), value))
            t:finish(2)
        end)
    )

    -- defer: no standalone `Job()` parent or `CoroutineStart.ATOMIC`.
    pending("testOverriddenParent")

    -- defer: no `invokeOnCompletion`/`DisposableHandle` or `getCompleted`.
    pending("testIncompleteAsyncState")

    -- not-applicable: no dispatchers (`Dispatchers.Unconfined`); one LocalSet runs everything.
    pending("testIncompleteAsyncFastPath")

    -- adapted: `try/finally` is `async.finally`, whose cleanup cannot return a
    -- value (Kotlin's `return@async "Fail"` is ignored there too); await raises
    -- `JobCancelled` instead of `CancellationException`.
    it(
        "testAsyncWithFinally",
        runtest(function (t)
            t:expect(1)
            local d = async.async(function ()
                t:expect(3)
                async.finally(function ()
                    async.yield() -- to main, will cancel
                end,
                    function ()
                        t:expect(6) -- will go there on await
                    end)
                t:expect_unreached()
                return "Fail2"
            end)
            t:expect(2)
            async.yield() -- to async
            t:expect(4)
            assert.is_true(d:is_active() and not d:is_completed() and not d:is_cancelled())
            d:cancel()
            assert.is_true(not d:is_active() and not d:is_completed() and d:is_cancelled())
            t:expect(5)
            local err = error_of(function ()
                async.await(d) -- awaits
                t:expect_unreached() -- does not complete normally
            end)
            t:expect(7)
            assert.is_equal("JobCancelled", err.kind)
            assert.is_true(not d:is_active() and d:is_completed() and d:is_cancelled())
            t:finish(8)
        end)
    )
end)
