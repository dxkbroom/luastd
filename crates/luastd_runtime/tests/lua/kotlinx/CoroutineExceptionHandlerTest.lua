-- kotlin: kotlinx-coroutines-core/common/test/CoroutineExceptionHandlerTest.kt@1.11.0
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = require("luastd_test").runtest

describe("CoroutineExceptionHandlerTest", function ()
    -- not-applicable: luastd has no standalone non-supervisor Job or
    -- CoroutineExceptionHandler context element; its unhandled handler is
    -- runtime-wide and configured by the host.
    pending("testJob")

    -- adapted: attach the launch to a deferred in a supervisor scope, then
    -- inspect the parent's failure; runtest also verifies no unhandled failure
    -- was reported, standing in for the absent per-coroutine handler callback.
    it(
        "testCompletableDeferred",
        runtest(function (t)
            async.supervisor_scope(function (scope)
                t:expect(1)
                local parent = scope:async(function () async.await_cancellation() end)
                local failure = luastd_test.TestException()
                local child = scope:launch(async.context(parent), function ()
                    error(failure, 0)
                end)
                t:expect(2)
                async.join(child)
                t:finish(3)
                assert.is_true(parent:is_cancelled())
                local ok, err = async.try_await(parent)
                assert.is_false(ok)
                assert.is_true(rawequal(failure, err))
            end)
        end)
    )
end)
