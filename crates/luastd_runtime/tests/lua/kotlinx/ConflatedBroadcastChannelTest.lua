-- kotlin: kotlinx-coroutines-core/common/test/channels/ConflatedBroadcastChannelTest.kt@1.11.0
local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

describe("ConflatedBroadcastChannelTest", function ()
    -- adapted: SharedFlow does not expose BroadcastChannel subscriptions; use
    -- concurrent take(1) collectors to verify multicast delivery and removal
    -- of one collector while another receives the same emission.
    it(
        "testConcurrentModification",
        runtest(function ()
            local shared = flow.mutable_shared_flow(0, 1, "DROP_OLDEST")
            local first, second
            local first_job = async.launch(function () first = shared:take(1):to_list() end)
            local second_job = async.launch(function () second = shared:take(1):to_list() end)
            async.yield()
            shared:emit(1)
            async.join(first_job)
            async.join(second_job)
            assert.same({ 1 }, first)
            assert.same({ 1 }, second)
        end)
    )

    -- adapted: no conflated broadcast channel with a value property or close
    -- state exists; verify Channel.CONFLATED keeps the latest buffered item
    -- and SharedFlow replay gives late collectors the latest emission.
    it(
        "testBasicScenario",
        runtest(function ()
            local channel = async.channel(async.CONFLATED)
            assert.is_true(channel:try_send("one"))
            assert.is_true(channel:try_send("two"))
            assert.is_true(channel:try_send("three"))
            assert.is_equal("three", channel:receive())

            local shared = flow.mutable_shared_flow(1, 0, "DROP_OLDEST")
            shared:emit("one")
            assert.same({ "one" }, shared:take(1):to_list())
            shared:emit("two")
            assert.same({ "two" }, shared:take(1):to_list())
        end)
    )

    -- adapted: SharedFlow replay represents the initial value for a late
    -- collector, but SharedFlow has no close operation or closed receive error.
    it(
        "testInitialValueAndReceiveClosed",
        runtest(function ()
            local shared = flow.mutable_shared_flow(1, 0, "DROP_OLDEST")
            shared:emit(1)
            assert.same({ 1 }, shared:take(1):to_list())
        end)
    )
end)
