-- kotlin: kotlinx-coroutines-core/common/test/JobExtensionsTest.kt@1.11.0
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("JobExtensionsTest", function ()
    -- adapted: luastd has no Job.ensureActive extension; check the current
    -- child coroutine through async.ensure_active and the Job state queries.
    it(
        "testIsActive",
        runtest(function ()
            local parent = async.supervisor_job()
            local checked = false
            local child = async.launch(async.context(parent), function ()
                async.ensure_active()
                checked = true
                async.await_cancellation()
            end)
            async.yield()
            assert.is_true(checked)
            assert.is_true(parent:is_active())
            async.ensure_active()
            parent:cancel()
            async.join(child)
            assert.is_true(parent:is_cancelled())
            assert.is_true(child:is_cancelled())
        end)
    )

    -- adapted: Job.complete/ensureActive extensions are absent; verify the
    -- equivalent lifecycle state of an ordinarily completed launched job.
    it(
        "testIsCompleted",
        runtest(function ()
            local ensured_active = false
            local job = async.launch(function ()
                async.ensure_active()
                ensured_active = true
            end)
            async.join(job)
            assert.is_true(ensured_active)
            assert.is_true(job:is_completed())
            assert.is_false(job:is_active())
            assert.is_false(job:is_cancelled())
        end)
    )

    -- adapted: Job.ensureActive on a failed job is absent; verify failure
    -- completion and cancellation state through the exposed Job API.
    it(
        "testIsCancelled",
        runtest({ unhandled = { "TestException" } }, function ()
            local failed = luastd_test.TestException()
            async.supervisor_scope(function (scope)
                local job = scope:launch(function ()
                    async.ensure_active()
                    error(failed, 0)
                end)
                async.join(job)
                assert.is_true(job:is_completed())
                assert.is_false(job:is_active())
                assert.is_true(job:is_cancelled())
            end)
        end)
    )

    -- adapted: luastd has no arbitrary EmptyCoroutineContext.ensureActive
    -- extension; the current active coroutine passes async.ensure_active.
    it(
        "testEnsureActiveWithEmptyContext",
        runtest(function ()
            async.ensure_active()
            assert.is_true(async.current():is_active())
        end)
    )

    -- adapted: Kotlin's Job.job extension is absent; verify the available
    -- CoroutineContext:job extraction and context construction round-trip.
    it(
        "testJobExtension",
        runtest(function ()
            local current_job = async.current():coroutine_context():job()
            assert.is_true(current_job ~= nil)
            assert.is_true(current_job:is_active())
            local context = async.context(current_job)
            assert.is_true(rawequal(context:job(), current_job))
        end)
    )
end)
