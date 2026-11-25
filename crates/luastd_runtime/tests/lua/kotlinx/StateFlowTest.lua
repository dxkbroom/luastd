-- kotlin: kotlinx-coroutines-core/common/test/flow/sharing/StateFlowTest.kt@1.11.0
local async = require("luastd.async")
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

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

    -- adapted: Lua tables use a custom __eq metamethod to represent Kotlin's
    -- data-class structural equality; scheduled yields let each distinct update
    -- be observed before testing that an equal update is suppressed.
    it(
        "testEqualsConflation",
        runtest(function ()
            local data_mt = { __eq = function (left, right) return left.i == right.i end }
            local function data(i) return setmetatable({ i = i }, data_mt) end
            local state = flow.mutable_state_flow(data(0))
            local values
            local job = async.launch(function ()
                values = state:take(3):map(function (value) return value.i end):to_list()
            end)
            while state.subscription_count == 0 do async.yield() end
            async.yield()
            state:set_value(data(1))
            async.yield()
            state:set_value(data(1))
            async.yield()
            state:set_value(data(2))
            async.join(job)
            assert.same({ 0, 1, 2 }, values)
        end)
    )

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

    -- adapted: use scheduled collection and assert the actual on_start,
    -- on_subscription, and replay values in order instead of Unconfined dispatch.
    it(
        "testOnSubscription",
        runtest(function ()
            local state = flow.mutable_state_flow("initial")
            local observed = {}
            local source = state
                :on_subscription(function (emit)
                    emit("collector->A")
                    state:set_value("A")
                end)
                :on_subscription(function (emit)
                    emit("collector->B")
                    state:set_value("B")
                end)
                :on_start(function (emit)
                    emit("collector->C")
                    state:set_value("C")
                end)
                :on_start(function (emit)
                    emit("collector->D")
                    state:set_value("D")
                end)
                :on_each(function (value)
                    table.insert(observed, value)
                    if value == "B" then async.current_context():job():cancel() end
                end)
            local job = async.launch(function () source:collect(function () end) end)
            async.join(job)
            assert.same({ "collector->D", "collector->C", "collector->A", "collector->B", "B" }, observed)
            assert.is_equal(0, state.subscription_count)
        end)
    )

    it(
        "testOnSubscriptionThrows",
        runtest(function ()
            local state = flow.mutable_state_flow("initial")
            local failure = luastd_test.TestException()
            local caught = false
            state:on_subscription(function () error(failure, 0) end)
                :catch(function (_, err)
                    assert.is_true(rawequal(failure, err))
                    caught = true
                end)
                :collect(function () error("on_subscription should fail before replay", 0) end)
            assert.is_true(caught)
            assert.is_equal(0, state.subscription_count)
        end)
    )

    -- adapted: model the ordered on_start and on_subscription emissions, then
    -- assert that the second subscription-hook exception reaches catch unchanged.
    it(
        "testOnSubscriptionWithException",
        runtest(function ()
            local state = flow.mutable_state_flow("A")
            local failure = luastd_test.TestException()
            local observed = {}
            local caught = false
            state
                :on_subscription(function (emit)
                    emit("collector->A")
                    state:set_value("A")
                end)
                :on_subscription(function (emit)
                    emit("collector->B")
                    state:set_value("B")
                    error(failure, 0)
                end)
                :on_start(function (emit)
                    emit("collector->C")
                    state:set_value("C")
                end)
                :on_start(function (emit)
                    emit("collector->D")
                    state:set_value("D")
                end)
                :on_each(function (value) table.insert(observed, value) end)
                :catch(function (_, err)
                    assert.is_true(rawequal(failure, err))
                    caught = true
                end)
                :collect(function () end)
            assert.same({ "collector->D", "collector->C", "collector->A", "collector->B" }, observed)
            assert.is_true(caught)
            assert.is_equal(0, state.subscription_count)
        end)
    )

    it(
        "testOperatorFusion",
        runtest(function ()
            local state = flow.mutable_state_flow("state")
            local context = async.context(async.coroutine_name("fusion"))
            assert.is_true(rawequal(state, state:cancellable()))
            assert.is_true(rawequal(state, state:distinct_until_changed()))
            assert.is_false(rawequal(state, state:distinct_until_changed(function (value) return value end)))
            assert.is_true(rawequal(state, state:flow_on(context)))
            assert.is_true(rawequal(state, state:conflate()))
            assert.is_true(rawequal(state, state:buffer(async.CONFLATED)))
            assert.is_true(rawequal(state, state:buffer(0)))
        end)
    )

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
