-- Port of kotlinx.coroutines' AwaitTest (see AGENTS.md, "Kotlin test
-- ports"). luastd has `async.await_all` and `async.join`, but no lazy jobs,
-- CompletableDeferred, or `joinAll` helper.
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

-- kotlin: kotlinx-coroutines-core/common/test/AwaitTest.kt@1.11.0
describe("AwaitTest", function ()
    it(
        "testAwaitAll",
        runtest(function (t)
            t:expect(1)
            local first = async.async(function ()
                t:expect(3)
                return "OK"
            end)
            local second = async.async(function ()
                async.yield()
                t:expect(4)
                return 1
            end)
            t:expect(2)
            assert.is_true(second:is_active())
            local a, b = async.await_all(first, second)
            assert.is_equal("OK", a)
            assert.is_equal(1, b)
            t:expect(5)
            assert.is_true(first:is_completed() and second:is_completed())
            assert.is_false(first:is_cancelled() or second:is_cancelled())
            t:finish(6)
        end)
    )

    -- defer: no `CoroutineStart.LAZY` or lazy deferred start operation.
    pending("testAwaitAllLazy")

    it(
        "testAwaitAllTyped",
        runtest(function ()
            local d1 = async.async(function () return 1 end)
            local d2 = async.async(function () return "" end)
            local a, b = async.await_all(d1, d2)
            assert.is_equal(1, a)
            assert.is_equal("", b)
        end)
    )

    -- adapted: contain the failing deferreds in a supervisor scope so the
    -- failure can be inspected and its unaffected sibling can be cancelled.
    it(
        "testAwaitAllExceptionally",
        runtest(function (t)
            async.supervisor_scope(function (scope)
                t:expect(1)
                local first = scope:async(function ()
                    t:expect(3)
                    return "OK"
                end)
                local failed = scope:async(function ()
                    async.yield()
                    error(luastd_test.TestException())
                end)
                local sibling = scope:async(function ()
                    t:expect(4)
                    async.delay(math.huge)
                end)
                t:expect(2)
                local err = error_of(function () async.await_all(first, failed, sibling) end)
                assert.is_equal("TestException", err.kind)
                assert.is_true(sibling:is_active())
                sibling:cancel()
                async.join(sibling)
                t:expect(5)
                t:finish(6)
            end)
        end)
    )

    -- adapted: both errors remain independently awaitable in a supervisor
    -- scope; `await_all` reports the first failed argument.
    it(
        "testAwaitAllMultipleExceptions",
        runtest(function (t)
            async.supervisor_scope(function (scope)
                local first = scope:async(function ()
                    t:expect(2)
                    error(luastd_test.TestException())
                end)
                local second = scope:async(function ()
                    async.yield()
                    error(luastd_test.TestException())
                end)
                t:expect(1)
                local err = error_of(function () async.await_all(first, second) end)
                assert.is_equal("TestException", err.kind)
                t:expect(3)
                t:finish(4)
            end)
        end)
    )

    it(
        "testAwaitAllCancellation",
        runtest(function (t)
            local outer = async.async(function ()
                local inner = async.async(function () async.delay(math.huge) end)
                async.await_all(inner)
                t:expect_unreached()
            end)
            async.yield()
            assert.is_true(outer:is_active())
            outer:cancel()
            async.join(outer)
            assert.is_true(outer:is_cancelled())
            t:finish(1)
        end)
    )

    it(
        "testAwaitAllPartiallyCompleted",
        runtest(function (t)
            local first = async.async(function ()
                t:expect(1)
                return 1
            end)
            assert.is_equal(1, async.await(first))
            local second = async.async(function ()
                t:expect(3)
                return 2
            end)
            t:expect(2)
            local a, b = async.await_all(first, second)
            assert.is_equal(1, a)
            assert.is_equal(2, b)
            t:finish(4)
        end)
    )

    -- adapted: a failed deferred does not cancel its supervisor sibling; the
    -- failed wait is caught as an ordinary error, then the sibling is joined.
    it(
        "testAwaitAllPartiallyCompletedExceptionally",
        runtest(function (t)
            async.supervisor_scope(function (scope)
                local failed = scope:async(function ()
                    t:expect(1)
                    error(luastd_test.TestException())
                end)
                async.yield()
                local sibling = scope:async(function () t:expect(4) end)
                t:expect(2)
                local err = error_of(function () async.await_all(failed, sibling) end)
                assert.is_equal("TestException", err.kind)
                t:expect(3)
                assert.is_true(sibling:is_active())
                async.await(sibling)
                assert.is_true(failed:is_completed() and sibling:is_completed())
                t:finish(5)
            end)
        end)
    )

    -- defer: no CompletableDeferred or externally completed deferreds.
    pending("testAwaitAllFullyCompleted")
    -- defer: no CompletableDeferred or collection-based `awaitAll` extension.
    pending("testAwaitOnSet")
    -- defer: no CompletableDeferred or externally completed failed deferreds.
    pending("testAwaitAllFullyCompletedExceptionally")

    it(
        "testAwaitAllSameJobMultipleTimes",
        runtest(function ()
            local deferred = async.async(function () return "OK" end)
            local a, b, c = async.await_all(deferred, deferred, deferred)
            assert.is_equal("OK", a)
            assert.is_equal("OK", b)
            assert.is_equal("OK", c)
        end)
    )

    -- adapted: `try_await` exposes the failed result as a value; duplicate
    -- waits are covered without swallowing the failure.
    it(
        "testAwaitAllSameThrowingJobMultipleTimes",
        runtest(function ()
            async.supervisor_scope(function (scope)
                local deferred = scope:async(function () error(luastd_test.TestException()) end)
                local ok, err = async.try_await(deferred)
                assert.is_false(ok)
                assert.is_equal("TestException", err.kind)
                local ok_again, same_err = async.try_await(deferred)
                assert.is_false(ok_again)
                assert.is_true(rawequal(err, same_err))
            end)
        end)
    )

    it(
        "testAwaitAllEmpty",
        runtest(function (t)
            t:expect(1)
            assert.is_nil(async.await_all())
            t:finish(2)
        end)
    )

    -- adapted: the current surface has `join`, so wait for each launched job
    -- in argument order instead of using Kotlin's `joinAll` helper.
    it(
        "testJoinAll",
        runtest(function (t)
            local first = async.launch(function () t:expect(2) end)
            local second = async.async(function ()
                t:expect(3)
                return "OK"
            end)
            local third = async.launch(function () t:expect(4) end)
            t:expect(1)
            for _, job in ipairs({ first, second, third }) do
                async.join(job)
            end
            t:finish(5)
        end)
    )

    -- defer: no lazy launch or `CoroutineStart.LAZY`.
    pending("testJoinAllLazy")

    -- adapted: join each job; as in Kotlin, joining does not rethrow a
    -- deferred's failure.
    it(
        "testJoinAllExceptionally",
        runtest(function (t)
            async.supervisor_scope(function (scope)
                local first = scope:launch(function () t:expect(2) end)
                local failed = scope:async(function ()
                    t:expect(3)
                    error(luastd_test.TestException())
                end)
                local third = scope:async(function () t:expect(4) end)
                t:expect(1)
                async.join(first)
                async.join(failed)
                async.join(third)
                t:finish(5)
            end)
        end)
    )

    it(
        "testJoinAllCancellation",
        runtest(function (t)
            local outer = async.launch(function ()
                local inner = async.launch(function () async.delay(math.huge) end)
                async.join(inner)
                t:expect_unreached()
            end)
            t:expect(1)
            async.yield()
            outer:cancel()
            async.join(outer)
            t:finish(2)
        end)
    )

    it(
        "testJoinAllAlreadyCompleted",
        runtest(function (t)
            local job = async.launch(function () t:expect(1) end)
            async.join(job)
            t:expect(2)
            async.join(job)
            t:finish(3)
        end)
    )

    it(
        "testJoinAllEmpty",
        runtest(function (t)
            t:expect(1)
            for _, job in ipairs({}) do
                async.join(job)
            end
            t:finish(2)
        end)
    )

    it(
        "testJoinAllSameJob",
        runtest(function ()
            local job = async.launch(function () end)
            async.join(job)
            async.join(job)
            async.join(job)
        end)
    )

    it(
        "testJoinAllSameJobExceptionally",
        runtest(function ()
            async.supervisor_scope(function (scope)
                local job = scope:async(function () error(luastd_test.TestException()) end)
                async.join(job)
                async.join(job)
                async.join(job)
            end)
        end)
    )

    -- defer: no CompletableDeferred or Deferred delegation/wrapper mechanism.
    pending("testAwaitAllDelegates")
    -- defer: no CompletableDeferred, Deferred delegation, or cancellable
    -- deferred interface to wrap.
    pending("testCancelAwaitAllDelegate")
end)
