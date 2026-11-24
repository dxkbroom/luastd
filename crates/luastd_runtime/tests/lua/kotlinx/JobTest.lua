-- kotlin: kotlinx-coroutines-core/common/test/JobTest.kt@1.11.0
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("JobTest", function ()
    -- adapted: Job exposes state but no parent property or standalone Job()
    -- constructor; verify the lifecycle of a supervisor_job handle.
    it("testState", runtest(function ()
        local job = async.supervisor_job()
        assert.is_true(job:is_active())
        assert.is_false(job:is_cancelled())
        assert.is_false(job:is_completed())
        job:cancel()
        assert.is_false(job:is_active())
        assert.is_true(job:is_cancelled())
        assert.is_true(job:is_completed())
    end))

    it("testHandler", runtest(function ()
        local job = async.launch(function () async.await_cancellation() end)
        local fire_count = 0
        job:on_cancel(function () fire_count = fire_count + 1 end)
        async.yield()
        assert.is_true(job:is_active())
        assert.is_equal(0, fire_count)
        job:cancel()
        async.join(job)
        assert.is_true(job:is_cancelled())
        assert.is_equal(1, fire_count)
        job:cancel()
        assert.is_equal(1, fire_count)
    end))

    it("testManyHandlers", runtest(function ()
        local job = async.launch(function () async.await_cancellation() end)
        local fire_counts = {}
        for i = 1, 100 do
            fire_counts[i] = 0
            job:on_cancel(function () fire_counts[i] = fire_counts[i] + 1 end)
        end
        async.yield()
        for i = 1, 100 do assert.is_equal(0, fire_counts[i]) end
        job:cancel()
        async.join(job)
        assert.is_true(job:is_cancelled())
        for i = 1, 100 do assert.is_equal(1, fire_counts[i]) end
        job:cancel()
        for i = 1, 100 do assert.is_equal(1, fire_counts[i]) end
    end))

    -- not-applicable: on_cancel does not return a disposable registration
    -- handle, so a handler cannot unregister itself during notification.
    pending("testUnregisterInHandler")

    -- not-applicable: the Job API has no DisposableHandle for registrations.
    pending("testManyHandlersWithUnregister")

    -- adapted: Lua cancellation handlers ignore callback errors; verify each
    -- registered callback still runs once even when it raises.
    it("testExceptionsInHandler", runtest(function ()
        local job = async.launch(function () async.await_cancellation() end)
        local fire_counts = {}
        for i = 1, 100 do
            fire_counts[i] = 0
            job:on_cancel(function ()
                fire_counts[i] = fire_counts[i] + 1
                error(luastd_test.TestException())
            end)
        end
        async.yield()
        job:cancel()
        async.join(job)
        assert.is_true(job:is_cancelled())
        for i = 1, 100 do assert.is_equal(1, fire_counts[i]) end
    end))

    it("testCancelledParent", runtest(function ()
        local parent = async.supervisor_job()
        parent:cancel()
        assert.is_true(parent:is_cancelled())
        local child = async.launch(async.context(parent), function ()
            error("child of cancelled parent should not run")
        end)
        assert.is_true(child:is_cancelled())
        async.join(child)
    end))

    -- not-applicable: on_cancel has no registration handle to dispose.
    pending("testDisposeSingleHandler")

    -- not-applicable: on_cancel has no registration handles to dispose.
    pending("testDisposeMultipleHandler")

    -- adapted: a supervisor_job parent and async.join verify cancellation
    -- waits for attached children and their non-cancellable cleanup.
    it("testCancelAndJoinParentWaitChildren", runtest(function (t)
        local parent = async.supervisor_job()
        local child = async.launch(async.context(parent), function ()
            t:expect(3)
            async.finally(function () async.delay(math.huge) end, function ()
                t:expect(5)
            end)
        end)
        t:expect(1)
        t:expect(2)
        async.yield()
        t:expect(4)
        parent:cancel()
        async.join(parent)
        async.join(child)
        t:finish(6)
    end))

    it("testOnCancellingHandler", runtest(function (t)
        local job = async.launch(function ()
            t:expect(2)
            async.delay(math.huge)
        end)
        job:on_cancel(function () t:expect(3) end)
        t:expect(1)
        async.yield()
        job:cancel()
        async.join(job)
        t:finish(4)
    end))

    -- not-applicable: on_cancel fires only after cancellation; the API has no
    -- on-cancelling completion handler that also fires on normal exit.
    pending("testInvokeOnCancellingFiringOnNormalExit")

    -- adapted: there is no ATOMIC launch mode; cancellation before the normal
    -- launched body starts verifies the runtime's cancellable start behavior.
    it("testOverriddenParent", runtest(function ()
        local parent = async.supervisor_job()
        local child = async.launch(async.context(parent), function () error("body should stay cancelled") end)
        parent:cancel()
        async.join(child)
        assert.is_true(child:is_cancelled())
    end))

    -- adapted: a coroutine child is cancelled without cancelling its parent.
    it("testJobWithParentCancelNormally", runtest(function ()
        local parent = async.supervisor_job()
        local child = async.launch(async.context(parent), function () async.await_cancellation() end)
        async.yield()
        child:cancel()
        async.join(child)
        assert.is_true(child:is_cancelled())
        assert.is_false(parent:is_cancelled())
    end))

    -- not-applicable: constructing a non-supervisor standalone Job and
    -- observing child failure cancel that parent are not exposed together.
    pending("testJobWithParentCancelException")

    -- adapted: the parent relation is not observable; assert the launched
    -- child reaches the same completed, inactive, non-cancelled state.
    it("testIncompleteJobState", runtest(function ()
        local job = async.launch(function () end)
        async.join(job)
        assert.is_true(job:is_completed())
        assert.is_false(job:is_active())
        assert.is_false(job:is_cancelled())
    end))

    -- not-applicable: Job exposes no children iterator/property to inspect.
    pending("testChildrenWithIncompleteState")
end)
