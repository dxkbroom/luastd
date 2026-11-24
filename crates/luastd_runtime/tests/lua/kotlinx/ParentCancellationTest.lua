-- kotlin: kotlinx-coroutines-core/common/test/ParentCancellationTest.kt@1.11.0
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

local function expect_scope_failure(body)
    local failure = luastd_test.TestException()
    local ok, err = async.try_scope(function (scope) body(scope, failure) end)
    assert.is_false(ok)
    assert.is_equal("TestException", err.kind)
    assert.is_true(async.current():is_active())
end

describe("ParentCancellationTest", function ()
    -- adapted: there is no standalone non-supervisor Job constructor; a
    -- structured scope with a failing child models its parent-cancellation path.
    it(
        "testJobChild",
        runtest(function ()
            expect_scope_failure(function (scope, failure)
                scope:launch(function () error(failure, 0) end)
            end)
        end)
    )

    -- not-applicable: the Kotlin assertion requires observing a supervisor's
    -- unhandled child exception; luastd exposes no CoroutineExceptionHandler,
    -- and the runtime test harness rejects unhandled child errors.
    pending("testSupervisorJobChild")

    -- not-applicable: the child failure cancels the deferred parent but is
    -- also reported as unhandled; there is no handler API to consume that
    -- report while inspecting the parent's cancellation state.
    pending("testCompletableDeferredChild")

    it(
        "testLaunchChild",
        runtest(function ()
            expect_scope_failure(function (scope, failure)
                scope:launch(function () error(failure, 0) end)
            end)
        end)
    )

    -- adapted: await the failing deferred inside a recoverable structured
    -- scope; luastd cancellation itself remains uncatchable (ADR 0005).
    it(
        "testAsyncChild",
        runtest(function ()
            expect_scope_failure(function (scope, failure)
                local child = scope:async(function () error(failure, 0) end)
                local ok, err = async.try_await(child)
                assert.is_false(ok)
                error(err, 0)
            end)
        end)
    )

    it(
        "testProduceChild",
        runtest(function ()
            expect_scope_failure(function ()
                async.produce(function () error(luastd_test.TestException(), 0) end)
            end)
        end)
    )

    -- not-applicable: the deprecated BroadcastChannel builder is not exposed.
    pending("testBroadcastChild")

    -- not-applicable: Kotlin asserts the supervisor's unhandled-exception
    -- callback; luastd has no handler API and the harness fails on that report.
    pending("testSupervisorChild")

    it(
        "testCoroutineScopeChild",
        runtest(function ()
            expect_scope_failure(function ()
                async.scope(function () error(luastd_test.TestException(), 0) end)
            end)
        end)
    )

    it(
        "testWithContextChild",
        runtest(function ()
            expect_scope_failure(function ()
                async.with_context(async.context(async.coroutine_name("fail")), function ()
                    error(luastd_test.TestException(), 0)
                end)
            end)
        end)
    )

    it(
        "testWithTimeoutChild",
        runtest(function ()
            expect_scope_failure(function ()
                async.with_timeout(1000, function () error(luastd_test.TestException(), 0) end)
            end)
        end)
    )
end)
