-- Port of kotlinx.coroutines' SupervisorTest (see AGENTS.md, "Kotlin test
-- ports"). luastd's supervisor boundary is `async.supervisor_scope`; it has
-- no standalone SupervisorJob, Job parent, or start modes.
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

--- Kotlin's `try { ... } catch (e: ...)`: the error `fn` raised.
---@async
---@param fn async fun()
---@return any
local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return err
end

-- kotlin: kotlinx-coroutines-core/common/test/SupervisorTest.kt@1.11.0
describe("SupervisorTest", function ()
    -- defer: no standalone `SupervisorJob()` or `joinAll`; launch failures are
    -- reported to the host's unhandled-failure handler instead.
    pending("testSupervisorJob")

    it(
        "testSupervisorScope",
        runtest({ unhandled = { "TestException1", "TestException2" } }, function (t)
            local value = async.supervisor_scope(function (scope)
                scope:launch(function () error(luastd_test.TestException1()) end)
                scope:launch(function () error(luastd_test.TestException2()) end)
                return "OK"
            end)
            assert.is_equal("OK", value)
            t:finish(1)
        end)
    )

    it(
        "testSupervisorScopeIsolation",
        runtest({ unhandled = { "TestException2" } }, function (t)
            local result = async.supervisor_scope(function (scope)
                t:expect(1)
                local job = scope:launch(function ()
                    t:expect(2)
                    async.delay(math.huge)
                end)
                local failing_job = scope:launch(function ()
                    t:expect(3)
                    error(luastd_test.TestException2())
                end)
                async.join(failing_job)
                async.yield()
                t:expect(4)
                assert.is_true(job:is_active())
                assert.is_false(job:is_cancelled())
                job:cancel()
                return "OK"
            end)
            assert.is_equal("OK", result)
            t:finish(5)
        end)
    )

    it(
        "testThrowingSupervisorScope",
        runtest({}, function (t)
            local child, supervisor_job
            local err = error_of(function ()
                t:expect(1)
                async.supervisor_scope(function (scope)
                    child = scope:async(function ()
                        async.finally(function ()
                            async.delay(math.huge)
                        end,
                            function ()
                                t:expect(3)
                            end)
                    end)
                    t:expect(2)
                    async.yield()
                    supervisor_job = scope:coroutine_context():job()
                    error(luastd_test.TestException2())
                end)
            end)
            assert.is_equal("TestException2", err.kind)
            assert.is_true(child:is_cancelled())
            assert.is_true(supervisor_job ~= nil and supervisor_job:is_cancelled())
            t:finish(4)
        end)
    )

    -- adapted: luastd has no `CoroutineStart.UNDISPATCHED`; yield to start the
    it(
        "testSupervisorThrows",
        runtest({}, function (t)
            local err = error_of(function ()
                t:expect(1)
                async.supervisor_scope(function (scope)
                    scope:launch(function ()
                        t:expect(2)
                        async.delay(math.huge)
                    end)
                    scope:launch(function ()
                        t:expect(3)
                        async.delay(math.huge)
                    end)
                    async.yield()
                    t:expect(4)
                    error(luastd_test.TestException1())
                end)
            end)
            assert.is_equal("TestException1", err.kind)
            t:finish(5)
        end)
    )
    -- cleanup but keeps the body's cancellation over a cleanup error (ADR 0005).
    -- Kotlin reports that cleanup error as unhandled; luastd keeps the body error.
    it(
        "testSupervisorThrowsWithFailingChild",
        runtest({}, function (t)
            local cleanup_ran = false
            local err = error_of(function ()
                async.supervisor_scope(function (scope)
                    scope:launch(function ()
                        async.finally(function ()
                            async.delay(1000)
                        end,
                            function ()
                                cleanup_ran = true
                                error(luastd_test.TestException2())
                            end)
                    end)
                    async.yield()
                    error(luastd_test.TestException1())
                end)
            end)
            assert.is_equal("TestException1", err.kind)
            assert.is_true(cleanup_ran)
            t:finish(1)
        end)
    )

    -- child before cancelling its parent, then check its cancellation cleanup.
    it(
        "testSupervisorScopeExternalCancellation",
        runtest({}, function (t)
            local child, child_finished
            local outer = async.launch(function ()
                async.supervisor_scope(function (scope)
                    child = scope:launch(function ()
                        async.finally(function ()
                            async.delay(math.huge)
                        end,
                            function ()
                                t:expect(2)
                                child_finished = true
                            end)
                    end)
                end)
            end)
            async.yield()
            t:expect(1)
            outer:cancel()
            assert.is_true(child:is_cancelled())
            async.join(outer)
            assert.is_true(outer:is_cancelled())
            assert.is_true(child_finished)
            t:finish(3)
        end)
    )

    -- defer: a standalone `SupervisorJob()` parent and deferred parent links
    -- are not part of the current API.
    pending("testAsyncCancellation")

    -- defer: no standalone `Job()` parent or `SupervisorJob(parent)`.
    pending("testSupervisorWithParentCancelNormally")
    -- defer: no standalone `Job()` parent or `SupervisorJob(parent)`.
    pending("testSupervisorWithParentCancelException")

    -- adapted: luastd delivers cancellation at the next suspension and does
    -- not enter the body's later error path (ADR 0005).
    it(
        "testSupervisorScopeCancellationVsException",
        runtest({}, function (t)
            local after_scope = false
            local job = async.launch(function (self)
                async.supervisor_scope(function ()
                    self:cancel()
                    async.yield()
                    error(luastd_test.TestException1())
                end)
                after_scope = true
            end)
            async.join(job)
            assert.is_true(job:is_cancelled())
            assert.is_false(after_scope)
            t:finish(1)
        end)
    )

    -- defer: no standalone SupervisorJob or CoroutineExceptionHandler.
    pending("testSupervisorJobCancellationException")

    -- adapted: when cancellation interrupts the child, `async.finally` runs
end)
