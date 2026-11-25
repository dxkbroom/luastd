local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/sharing/StateInTest.kt@1.11.0
describe("StateInTest", function ()
    -- defer: StateIn currently has no started-strategy fusion or wrapper identity semantics.
    pending("testOperatorFusion")

    -- adapted: state_in without an initial value waits for the first upstream emission;
    -- this flow completes immediately after producing the value, so no sharing Job is exposed.
    it(
        "testUpstreamCompletedNoInitialValue",
        runtest(function (t)
            local state = flow.of_one("OK"):state_in(async.current())
            assert.is_equal("OK", state.value)
            t:finish(1)
        end)
    )

    -- adapted: an upstream failure before the first value is returned to the waiting caller;
    -- Kotlin reports it through the sharing coroutine's exception handler.
    it(
        "testUpstreamFailedNoInitialValue",
        runtest(function (t)
            local failure = require("luastd_test").TestException()
            local source = flow.new(function () error(failure, 0) end)
            local ok, err = pcall(function () source:state_in(async.current()) end)
            assert.is_false(ok)
            assert.is_true(err == failure)
            t:finish(1)
        end)
    )

    -- adapted: eager state_in with an explicit nil initial value returns immediately;
    -- a scheduler yield lets the launched upstream update the value.
    it(
        "testUpstreamCompletedWithInitialValue",
        runtest(function (t)
            local state = flow.of_one("OK"):state_in(async.current(), nil)
            assert.is_nil(state.value)
            async.yield()
            assert.is_equal("OK", state.value)
            t:finish(1)
        end)
    )

    -- defer: observing a failure after returning the initial state requires access to the
    -- sharing Job's completion cause or a CoroutineExceptionHandler.
    pending("testUpstreamFailedWithInitialValue")

    -- defer: immediate background failures need the CoroutineExceptionHandler API.
    pending("testUpstreamFailedImmediatelyWithInitialValue")

    -- adapted: the no-initial overload suspends through the first upstream emission.
    it(
        "testSubscriptionByFirstSuspensionInStateFlow",
        runtest(function (t)
            local state = flow.of_one(1):state_in(async.current())
            assert.is_equal(1, state.value)
            t:finish(1)
        end)
    )

    -- not-applicable: Kotlin asserts catchable CancellationException propagation, while ADR 0005
    -- makes cancellation uncatchable and StateIn has no separate canceled-scope cause surface.
    pending("testRethrowsCEOnCancelledScope")

    it(
        "testThrowsNoSuchElementExceptionOnEmptyFlow",
        runtest(function (t)
            local ok, err = pcall(function () flow.empty():state_in(async.current()) end)
            assert.is_false(ok)
            assert.is_equal("NoSuchElementException", err.kind)
            assert.is_true(async.is_active())
            t:finish(1)
        end)
    )
end)
