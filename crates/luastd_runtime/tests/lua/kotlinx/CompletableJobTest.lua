-- kotlin: kotlinx-coroutines-core/common/test/CompletableJobTest.kt@1.11.0
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("CompletableJobTest", function ()
    -- adapted: luastd exposes completable_deferred rather than a standalone
    -- no-result CompletableJob; verify its first completion and lifecycle.
    it(
        "testComplete",
        runtest(function ()
            local job = async.completable_deferred()
            assert.is_true(job:is_active())
            assert.is_false(job:is_completed())
            assert.is_true(job:complete("done"))
            local ok, value = async.try_await(job)
            assert.is_true(ok)
            assert.is_equal("done", value)
            assert.is_true(job:is_completed())
            assert.is_false(job:is_active())
            assert.is_false(job:is_cancelled())
            assert.is_false(job:complete("again"))
        end)
    )

    -- adapted: completeExceptionally is represented by complete_exceptionally
    -- on a deferred; supervisor_scope isolates its failed child result.
    it(
        "testCompleteWithException",
        runtest(function ()
            async.supervisor_scope(function ()
                local job = async.completable_deferred()
                local failure = luastd_test.TestException()
                assert.is_true(job:is_active())
                assert.is_false(job:is_completed())
                assert.is_true(job:complete_exceptionally(failure))
                local ok, err = async.try_await(job)
                assert.is_false(ok)
                assert.is_true(rawequal(failure, err))
                assert.is_true(job:is_completed())
                assert.is_false(job:is_active())
                assert.is_true(job:is_cancelled())
                assert.is_false(job:complete_exceptionally(luastd_test.TestException()))
                assert.is_false(job:complete("again"))
            end)
        end)
    )

    -- adapted: deferred completion waits for attached children; cancel the
    -- child explicitly because Job exposes no external successful completion.
    it(
        "testCompleteWithChildren",
        runtest(function ()
            local parent = async.completable_deferred()
            local child = async.launch(async.context(parent), function () async.await_cancellation() end)
            async.yield()
            assert.is_true(parent:complete("done"))
            async.yield()
            assert.is_false(parent:is_completed())
            child:cancel()
            async.try_await(child)
            local ok, value = async.try_await(parent)
            assert.is_true(ok)
            assert.is_equal("done", value)
            assert.is_true(parent:is_completed())
        end)
    )

    -- not-applicable: these cases inspect a child's caught cancellation and
    -- exception cause; luastd cancellation bypasses Lua callbacks (ADR 0005).
    pending("testExceptionIsNotReportedToChildren")

    -- not-applicable: this inspects a child's caught cancellation and
    -- completion cause after exceptional parent completion (ADR 0005).
    pending("testCompleteExceptionallyDoesntAffectDeferred")
end)
