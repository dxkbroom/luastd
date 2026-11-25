-- Port of kotlinx.coroutines' CoroutineScopeTest (see AGENTS.md, "Kotlin test
-- ports"). Dispatcher APIs are outside luastd's coroutine model.
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/CoroutineScopeTest.kt@1.11.0
describe("CoroutineScopeTest", function ()
    it(
        "testScope",
        runtest(function (t)
            t:expect(1)
            local result = async.scope(function (scope)
                t:expect(2)
                scope:launch(function () t:expect(4) end)
                scope:launch(function (child)
                    t:expect(5)
                    child:launch(function () t:expect(7) end)
                    t:expect(6)
                end)
                t:expect(3)
                return 42
            end)
            assert.is_equal(42, result)
            async.yield()
            t:finish(8)
        end)
    )

    it(
        "testScopeCancelledFromWithin",
        runtest({ expected = "TestException2" }, function ()
            async.scope(function (scope)
                scope:launch(function () async.delay(math.huge) end)
                scope:launch(function () error(luastd_test.TestException2()) end)
            end)
        end)
    )

    it(
        "testExceptionFromWithin",
        runtest({ expected = "TestException1" }, function (t)
            t:expect(1)
            async.scope(function ()
                t:expect(2)
                t:finish(3)
                error(luastd_test.TestException1())
            end)
        end)
    )

    it(
        "testScopeBlockThrows",
        runtest({ expected = "TestException1" }, function ()
            async.scope(function (scope)
                scope:launch(function ()
                    async.finally(function ()
                        async.delay(math.huge)
                    end, function () end)
                end)
                async.yield()
                error(luastd_test.TestException1())
            end)
        end)
    )

    -- not-applicable: cancellation is not catchable at `pcall` boundaries (ADR 0005),
    -- so Kotlin's `catch (JobCancellationException)` cannot be ported directly.
    pending("testOuterJobIsCancelled")

    -- not-applicable: awaiting a failing child in its own cancelled scope raises the
    -- uncatchable caller cancellation (ADR 0005), before Kotlin's catch.
    pending("testAsyncCancellationFirst")
    -- not-applicable: same cancellation behavior as `testAsyncCancellationFirst`.
    pending("testAsyncCancellationSecond")

    -- adapted: `withContext` is not in luastd; the failing scope body still
    -- cancels its child and preserves the body's error.
    it(
        "testDocumentationExample",
        runtest(function (t)
            local cleanup_ran = false
            t:expect(1)
            local ok, err = pcall(function ()
                async.scope(function (scope)
                    local data = scope:launch(function ()
                        async.finally(function () async.delay(math.huge) end, function ()
                            cleanup_ran = true
                        end)
                    end)
                    async.yield()
                    error(luastd_test.TestException1())
                    async.join(data)
                    t:expect_unreached()
                end)
            end)
            assert.is_false(ok)
            assert.is_equal("TestException1", err.kind)
            assert.is_true(cleanup_ran)
            t:finish(2)
        end)
    )

    -- not-applicable: same cancellation-before-error difference as ADR 0005 documents;
    -- the Kotlin test catches the later exception after cancelling its job.
    pending("testCoroutineScopeCancellationVsException")

    -- not-applicable: luastd does not expose a configurable dispatcher.
    pending("testLaunchContainsDefaultDispatcher")
    -- not-applicable: luastd does not expose dispatcher composition.
    pending("testNewCoroutineContextDispatcher")
    -- not-applicable: luastd does not expose dispatcher composition.
    pending("testScopePlusContext")

    it(
        "testIncompleteScopeState",
        runtest(function ()
            local job
            async.scope(function (scope)
                job = scope:coroutine_context():job()
            end)
            async.join(job)
            assert.is_true(job:is_completed())
            assert.is_false(job:is_active())
            assert.is_false(job:is_cancelled())
        end)
    )

    -- not-applicable: luastd context activity is queried through its Job; it has no
    -- context-level isActive API for a context without a Job.
    pending("testIsActiveWithoutJob")
end)
