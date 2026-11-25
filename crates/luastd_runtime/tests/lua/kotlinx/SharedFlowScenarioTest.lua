-- kotlin: kotlinx-coroutines-core/common/test/flow/sharing/SharedFlowScenarioTest.kt@1.11.0
local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

describe("SharedFlowScenarioTest", function ()
    local function subscribe(scope, shared, on_value)
        local values = async.channel(16)
        local job = scope:launch(function ()
            shared:collect(function (value)
                if on_value then on_value(value) end
                values:send(value)
            end)
        end)
        while shared.subscription_count == 0 do
            async.yield()
        end
        return job, values
    end

    local function cancel_subscriber(shared, job)
        job:cancel()
        async.join(job)
        assert.is_equal(0, shared.subscription_count)
    end

    -- adapted: verifies replay and extra-buffer values with one paused collector;
    -- it does not exercise queued emitters or cancellation ordering.
    it(
        "testReplay1Extra2",
        runtest(function (t, scope)
            t:expect(1)
            local shared = flow.mutable_shared_flow(1, 2)
            for value = 1, 4 do
                shared:emit(value)
            end
            assert.same({ 4 }, shared.replay_cache)

            local entered = async.channel(1)
            local release = async.channel(0)
            local job, values = subscribe(scope, shared, function (value)
                if value == 4 then
                    entered:send(true)
                    release:receive()
                end
            end)
            assert.is_true(entered:receive())
            shared:emit(5)
            shared:emit(6)
            shared:emit(7)
            assert.same({ 7 }, shared.replay_cache)
            shared:reset_replay_cache()
            assert.same({}, shared.replay_cache)

            release:send(true)
            assert.same({ 4, 5, 6, 7 }, {
                values:receive(),
                values:receive(),
                values:receive(),
                values:receive()
            })
            shared:emit(8)
            assert.same({ 8 }, shared.replay_cache)
            assert.is_equal(8, values:receive())
            cancel_subscriber(shared, job)
            t:finish(2)
        end)
    )

    -- adapted: verifies replay replacement, reset idempotence, and live delivery;
    -- this leaves queued-emitter suspension to the dedicated deferred cases.
    it(
        "testReplay1",
        runtest(function (t, scope)
            t:expect(1)
            local shared = flow.mutable_shared_flow(1)
            shared:emit(0)
            shared:emit(1)
            shared:emit(2)
            assert.same({ 2 }, shared.replay_cache)
            shared:reset_replay_cache()
            assert.same({}, shared.replay_cache)
            shared:reset_replay_cache()
            assert.same({}, shared.replay_cache)
            shared:emit(3)
            shared:emit(4)
            assert.same({ 4 }, shared.replay_cache)

            local job, values = subscribe(scope, shared)
            assert.is_equal(4, values:receive())
            shared:emit(5)
            assert.same({ 5 }, shared.replay_cache)
            assert.is_equal(5, values:receive())
            shared:reset_replay_cache()
            assert.same({}, shared.replay_cache)
            cancel_subscriber(shared, job)
            t:finish(2)
        end)
    )

    -- adapted: no-subscriber DROP_OLDEST replay retains the final two values;
    -- the active subscriber check covers ordinary delivery, not overflow races.
    it(
        "testReplay2Extra2DropOldest",
        runtest(function (t, scope)
            t:expect(1)
            local shared = flow.mutable_shared_flow(2, 2, "DROP_OLDEST")
            for value = 0, 4 do
                shared:emit(value)
            end
            assert.same({ 3, 4 }, shared.replay_cache)

            local job, values = subscribe(scope, shared)
            assert.is_equal(3, values:receive())
            assert.is_equal(4, values:receive())
            shared:emit(5)
            assert.same({ 4, 5 }, shared.replay_cache)
            assert.is_equal(5, values:receive())
            shared:reset_replay_cache()
            assert.same({}, shared.replay_cache)
            cancel_subscriber(shared, job)
            t:finish(2)
        end)
    )

    -- defer: this asserts a fast-subscriber resume race while a queued emitter
    -- resumes; the current SharedFlow has no ordered emitter queue.
    pending("testResumeFastSubscriberOnResumedEmitter")

    -- defer: cancelling a subscriber must release multiple queued emitters in
    -- order; one-at-a-time backpressure is not equivalent.
    pending("testSuspendedConcurrentEmitAndCancelSubscriberReplay1")

    -- defer: this adds concurrent queued-emitter cancellation after filling
    -- replay plus extra capacity; the full queue lifecycle is not modeled.
    pending("testSuspendedConcurrentEmitAndCancelSubscriberReplay1ExtraBuffer1")
end)
