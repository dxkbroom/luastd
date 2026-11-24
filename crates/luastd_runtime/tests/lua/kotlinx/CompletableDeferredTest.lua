-- kotlin: kotlinx-coroutines-core/common/test/CompletableDeferredTest.kt@1.11.0
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

local function assert_fresh(deferred)
    assert.is_true(deferred:is_active())
    assert.is_false(deferred:is_cancelled())
    assert.is_false(deferred:is_completed())
end

local function assert_complete_ok(deferred, value)
    assert.is_false(deferred:is_active())
    assert.is_false(deferred:is_cancelled())
    assert.is_true(deferred:is_completed())
    local ok, result = async.try_await(deferred)
    assert.is_true(ok)
    assert.is_equal(value, result)
end

describe("CompletableDeferredTest", function ()
    it(
        "testFresh",
        runtest(function ()
            local deferred = async.completable_deferred()
            assert_fresh(deferred)
            deferred:cancel()
            async.join(deferred)
        end)
    )

    it(
        "testComplete",
        runtest(function ()
            local deferred = async.completable_deferred()
            assert.is_true(deferred:complete("OK"))
            local ok, value = async.try_await(deferred)
            assert.is_true(ok)
            assert.is_equal("OK", value)
            assert_complete_ok(deferred, "OK")
            assert.is_false(deferred:complete("OK"))
            assert_complete_ok(deferred, "OK")
        end)
    )

    -- not-applicable: Kotlin completes with a DisposableHandle returned from
    -- invokeOnCompletion; luastd exposes cancellation hooks but no completion
    -- handle or completion value object.
    pending("testCompleteWithIncompleteResult")

    it(
        "testCancelWithException",
        runtest(function ()
            async.supervisor_scope(function ()
                local deferred = async.completable_deferred()
                local failure = luastd_test.TestException()
                assert.is_true(deferred:complete_exceptionally(failure))
                local ok, err = async.try_await(deferred)
                assert.is_false(ok)
                assert.is_true(rawequal(failure, err))
                assert.is_false(deferred:is_active())
                assert.is_true(deferred:is_cancelled())
                assert.is_true(deferred:is_completed())
                assert.is_false(deferred:complete_exceptionally(failure))
                local repeated_ok, repeated_err = async.try_await(deferred)
                assert.is_false(repeated_ok)
                assert.is_true(rawequal(failure, repeated_err))
            end)
        end)
    )

    -- adapted: Result.success is not exposed; complete(value) has the same
    -- first-completion-wins behavior for a successful result.
    it(
        "testCompleteWithResultOK",
        runtest(function ()
            local deferred = async.completable_deferred()
            assert.is_true(deferred:complete("OK"))
            local ok, value = async.try_await(deferred)
            assert.is_true(ok)
            assert.is_equal("OK", value)
            assert_complete_ok(deferred, "OK")
            assert.is_false(deferred:complete("OK"))
            assert_complete_ok(deferred, "OK")
        end)
    )

    -- adapted: Result.failure is not exposed; complete_exceptionally(error)
    -- supplies the same failed deferred result.
    it(
        "testCompleteWithResultException",
        runtest(function ()
            async.supervisor_scope(function ()
                local deferred = async.completable_deferred()
                local failure = luastd_test.TestException()
                assert.is_true(deferred:complete_exceptionally(failure))
                local ok, err = async.try_await(deferred)
                assert.is_false(ok)
                assert.is_true(rawequal(failure, err))
                assert.is_false(deferred:complete_exceptionally(luastd_test.TestException()))
            end)
        end)
    )

    -- not-applicable: completable_deferred has no parent argument, and
    -- cancelling the current parent is uncatchable under ADR 0005.
    pending("testParentCancelsChild")

    it(
        "testParentActiveOnChildCompletion",
        runtest(function ()
            async.supervisor_scope(function (parent)
                local deferred = async.completable_deferred()
                assert_fresh(deferred)
                assert.is_true(parent:is_active())
                assert.is_true(deferred:complete("OK"))
                local ok, value = async.try_await(deferred)
                assert.is_true(ok)
                assert.is_equal("OK", value)
                assert_complete_ok(deferred, "OK")
                assert.is_true(parent:is_active())
            end)
        end)
    )

    -- not-applicable: exceptional child completion cancels its parent scope,
    -- whose cancellation cannot be caught for the test's post-cancel checks.
    pending("testParentCancelledOnChildException")

    it(
        "testParentActiveOnChildCancellation",
        runtest(function ()
            async.supervisor_scope(function (parent)
                local deferred = async.completable_deferred()
                assert_fresh(deferred)
                assert.is_true(parent:is_active())
                deferred:cancel()
                async.join(deferred)
                assert.is_false(deferred:is_active())
                assert.is_true(deferred:is_cancelled())
                assert.is_true(parent:is_active())
            end)
        end)
    )

    it(
        "testAwait",
        runtest(function (t)
            local deferred = async.completable_deferred()
            local waiter = async.launch(function ()
                t:expect(2)
                assert.is_equal("OK", async.await(deferred))
                t:expect(5)
                assert.is_equal("OK", async.await(deferred))
                t:expect(6)
            end)
            t:expect(1)
            async.yield()
            t:expect(3)
            assert.is_true(deferred:complete("OK"))
            t:expect(4)
            async.yield()
            async.join(waiter)
            t:finish(7)
        end)
    )

    -- adapted: luastd cancellation cannot be caught around await (ADR 0005);
    -- cancel the deferred then join it to verify attached child cleanup finishes.
    it(
        "testCancelAndAwaitParentWaitChildren",
        runtest(function (t)
            local parent = async.completable_deferred()
            local child = async.launch(async.context(parent), function ()
                t:expect(2)
                async.finally(function ()
                    async.await_cancellation()
                end,
                    function ()
                        t:expect(5)
                    end)
            end)
            t:expect(1)
            async.yield()
            t:expect(3)
            parent:cancel()
            t:expect(4)
            async.yield()
            local parent_ok = async.try_await(parent)
            assert.is_false(parent_ok)
            async.try_await(child)
            assert.is_true(parent:is_completed())
            t:finish(6)
        end)
    )

    -- adapted: check that join waits for the attached child after successful
    -- completion; luastd's await returns the value after the parent settles.
    it(
        "testCompleteAndAwaitParentWaitChildren",
        runtest(function (t)
            local parent = async.completable_deferred()
            local child = async.launch(async.context(parent), function ()
                t:expect(2)
                async.finally(function ()
                    async.await_cancellation()
                end,
                    function ()
                        t:expect(5)
                    end)
            end)
            t:expect(1)
            async.yield()
            t:expect(3)
            assert.is_true(parent:complete("OK"))
            t:expect(4)
            child:cancel()
            assert.is_equal("OK", async.await(parent))
            async.join(child)
            t:finish(6)
        end)
    )
end)
