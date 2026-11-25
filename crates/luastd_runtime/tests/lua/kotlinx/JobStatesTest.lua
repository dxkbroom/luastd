-- kotlin: kotlinx-coroutines-core/common/test/JobStatesTest.kt@1.11.0
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = require("luastd_test").runtest

describe("JobStatesTest", function ()
    -- adapted: Job exposes active/completed/cancelled snapshots but no parent
    -- getter or Completing state; verify observable states around child wait.
    it(
        "testNormalCompletion",
        runtest(function ()
            local gate = async.completable_deferred()
            local child_started = false
            local job = async.launch_lazy(function (scope)
                scope:launch(function ()
                    child_started = true
                    assert.is_equal("released", async.await(gate))
                end)
            end)
            assert.is_false(job:is_active())
            assert.is_false(job:is_completed())
            assert.is_false(job:is_cancelled())

            assert.is_true(job:start())
            async.yield()
            assert.is_true(child_started)
            assert.is_true(job:is_active())
            assert.is_false(job:is_completed())
            assert.is_false(job:is_cancelled())

            assert.is_true(gate:complete("released"))
            async.join(job)
            assert.is_false(job:is_active())
            assert.is_true(job:is_completed())
            assert.is_false(job:is_cancelled())
        end)
    )

    -- adapted: let a normal parent's child fail after the parent body returns;
    -- verify the public terminal Job state and runtest's unhandled error capture.
    it(
        "testCompletingFailed",
        runtest({ unhandled = { "TestException" } }, function ()
            local failure = luastd_test.TestException()
            async.supervisor_scope(function (supervisor)
                local child_started = false
                local job = supervisor:launch_lazy(function (scope)
                    scope:launch(function ()
                        child_started = true
                        async.yield()
                        error(failure, 0)
                    end)
                end)
                assert.is_false(job:is_active())
                assert.is_false(job:is_completed())
                assert.is_false(job:is_cancelled())
                assert.is_true(job:start())
                async.yield()
                assert.is_true(child_started)
                assert.is_true(job:is_active())
                assert.is_false(job:is_completed())
                assert.is_false(job:is_cancelled())
                async.join(job)
                assert.is_false(job:is_active())
                assert.is_true(job:is_completed())
                assert.is_true(job:is_cancelled())
            end)
        end)
    )

    -- adapted: the current Job API exposes terminal failure/cancellation but
    -- no Cancelling state or atomic child start; verify parent failure cancels
    -- an unstarted child and leaves the parent completed/cancelled.
    it(
        "testFailed",
        runtest({ unhandled = { "TestException" } }, function ()
            local failure = luastd_test.TestException()
            async.supervisor_scope(function (supervisor)
                local job = supervisor:launch_lazy(function (scope)
                    scope:launch(function () error("child should not start") end)
                    error(failure, 0)
                end)
                assert.is_false(job:is_active())
                assert.is_false(job:is_completed())
                assert.is_false(job:is_cancelled())
                assert.is_true(job:start())
                async.join(job)
                assert.is_false(job:is_active())
                assert.is_true(job:is_completed())
                assert.is_true(job:is_cancelled())
            end)
        end)
    )

    -- adapted: verify the public state snapshots before cancellation, while a
    -- child is being cancelled, and after the parent Job has joined.
    it(
        "testCancelling",
        runtest(function ()
            local child_started = false
            local job = async.launch_lazy(function (scope)
                scope:launch(function ()
                    child_started = true
                    async.await_cancellation()
                end)
            end)
            assert.is_false(job:is_active())
            assert.is_false(job:is_completed())
            assert.is_false(job:is_cancelled())
            assert.is_true(job:start())
            async.yield()
            assert.is_true(child_started)
            assert.is_true(job:is_active())
            assert.is_false(job:is_completed())
            assert.is_false(job:is_cancelled())

            job:cancel()
            assert.is_false(job:is_active())
            assert.is_false(job:is_completed())
            assert.is_true(job:is_cancelled())
            async.join(job)
            assert.is_false(job:is_active())
            assert.is_true(job:is_completed())
            assert.is_true(job:is_cancelled())
        end)
    )
end)
