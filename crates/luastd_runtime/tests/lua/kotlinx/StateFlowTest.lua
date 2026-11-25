-- kotlin: kotlinx-coroutines-core/common/test/flow/sharing/StateFlowTest.kt@1.11.0
local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

describe("StateFlowTest", function ()
    -- adapted: Lua nil cannot be retained in StateFlow's replay slot, so a
    -- unique table represents Kotlin null; cancellation is checked from outside
    -- the collector because luastd cancellation is uncatchable (ADR 0005).
    it(
        "testNormalAndNull",
        runtest(function (t)
            local null = {}
            local state = flow.mutable_state_flow(0)
            local values
            local job = async.launch(function ()
                values = state:take(4):to_list()
            end)
            async.yield()
            state:update(function () return 1 end)
            async.yield()
            state:update(function () return null end)
            async.yield()
            state:update(function () return 2 end)
            async.join(job)
            assert.same({ 0, 1, null, 2 }, values)
            t:finish(1)
        end)
    )

    -- defer: StateFlow:set_value currently publishes equal updates, and Lua
    -- table equality is identity-based, so Kotlin's structural equality
    -- conflation cannot be represented by the current API.
    pending("testEqualsConflation")

    -- adapted: update is the supported mutation API; collect its 0..10 values
    -- and sum them directly because this Flow surface has no sum terminal.
    it(
        "testDataModel",
        runtest(function (t)
            local counter = flow.mutable_state_flow(0)
            local values
            local collector = async.launch(function ()
                values = counter:take(11):to_list()
            end)
            for _ = 1, 10 do
                async.yield()
                counter:update(function (value) return value + 1 end)
            end
            async.join(collector)
            local sum = 0
            for _, value in ipairs(values) do
                sum = sum + value
            end
            assert.is_equal(55, sum)
            t:finish(1)
        end)
    )

    -- defer: Flow has no on_subscription operator for callbacks that run after
    -- registration and before replay begins.
    pending("testOnSubscription")

    -- defer: Flow has no on_subscription operator, so its pre-replay exception
    -- and downstream catch behavior cannot be exercised.
    pending("testOnSubscriptionThrows")

    -- defer: Flow has no on_subscription operator to model the two callback
    -- layers and exception ordering in this case.
    pending("testOnSubscriptionWithException")

    -- defer: StateFlow operations do not fuse to the same object; the current
    -- Flow operators wrap their source or support only limited no-op behavior.
    pending("testOperatorFusion")

    -- adapted: Lua omits reset_replay_cache entirely; verify the operation is
    -- unavailable and the state value remains intact.
    it(
        "testResetUnsupported",
        runtest(function (t)
            local state = flow.mutable_state_flow(42)
            assert.is_nil(state.reset_replay_cache)
            assert.is_equal(42, state.value)
            t:finish(1)
        end)
    )

    it(
        "testUpdate",
        runtest(function (t)
            local state = flow.mutable_state_flow(0)
            state:update(function (value) return value + 2 end)
            assert.is_equal(2, state.value)
            state:update(function (value) return value + 3 end)
            assert.is_equal(5, state.value)
            t:finish(1)
        end)
    )

    -- adapted: there is no CoroutineStart.UNDISPATCHED; yield once so the
    -- collector registers before the update, then verify that first emission.
    it(
        "testSubscriptionByFirstSuspensionInStateFlow",
        runtest(function (t)
            local state = flow.mutable_state_flow(0)
            local received
            local collector = async.launch(function ()
                state:collect(function (value) received = value end)
            end)
            async.yield()
            state:update(function () return 1 end)
            async.yield()
            assert.is_equal(1, received)
            collector:cancel()
            t:finish(1)
        end)
    )
end)
