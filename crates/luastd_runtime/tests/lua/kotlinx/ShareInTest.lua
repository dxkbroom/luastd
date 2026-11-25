-- Port of kotlinx.coroutines' ShareInTest.

local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/sharing/ShareInTest.kt@1.11.0
describe("ShareInTest", function ()
    -- adapted: the eager source is gated to finish before subscribers start;
    -- replay_cache and subscription_count verify all subscribers miss the value.
    it(
        "testReplay0Eager",
        runtest(function (t, scope)
            t:expect(1)
            local upstream_done = async.channel(0)
            local source = flow.new(function (emit)
                emit("OK")
                upstream_done:send(true)
            end)
            local shared = source:share_in(scope, 0)
            assert.is_true(upstream_done:receive())
            async.yield()
            assert.same({}, shared.replay_cache)

            local seen = {}
            local subscribers = {}
            for i = 1, 10 do
                subscribers[i] = scope:launch(function ()
                    shared:collect(function (value)
                        seen[#seen + 1] = value
                        t:expect_unreached()
                    end)
                end)
            end
            while shared.subscription_count < 10 do
                async.yield()
            end
            assert.is_equal(10, shared.subscription_count)
            assert.same({}, seen)
            for _, subscriber in ipairs(subscribers) do
                subscriber:cancel()
                async.join(subscriber)
            end
            assert.is_equal(0, shared.subscription_count)
            t:finish(2)
        end)
    )

    -- defer: sharing starts eagerly only; there is no lazy strategy to wait for
    -- the first subscriber before starting upstream.
    pending("testReplay0Lazy")

    -- defer: replay=1 is supported, but lazy startup and first-subscriber
    -- barriers are not available to distinguish the first subscriber.
    pending("testReplay1Lazy")

    -- adapted: verify that eager upstream completion leaves its replay value
    -- cached; a completion rendezvous replaces inspection of the sharing Job.
    it(
        "testUpstreamCompleted",
        runtest(function (t, scope)
            t:expect(1)
            local completed = async.channel(0)
            local source = flow.of_one("OK"):on_completion(function (err)
                assert.is_nil(err)
                completed:send(true)
            end)
            local shared = source:share_in(scope, 1)
            assert.same({}, shared.replay_cache)
            assert.is_true(completed:receive())
            async.yield()
            assert.same({ "OK" }, shared.replay_cache)
            t:finish(2)
        end)
    )

    -- defer: the case inspects a sharing Job's completion exception; share_in
    -- returns a SharedFlow and exposes no Job handle.
    pending("testUpstreamFailed")

    -- defer: the runtime has no WhileSubscribed start/stop policy driven by
    -- subscriber counts.
    pending("testWhileSubscribedBasic")

    -- defer: custom subscription-count thresholds are not supported by the
    -- eager-only share_in API.
    pending("testWhileSubscribedCustomAtLeast1")
    pending("testWhileSubscribedCustomAtLeast2")

    -- defer: lazy startup after a cancelled first subscription is unsupported.
    pending("testShouldStart")

    -- defer: state_in with lazy startup is not available.
    pending("testShouldStartScalar")

    -- defer: state_in and subscription-first-suspension behavior are not
    -- represented by the current SharedFlow API.
    pending("testSubscriptionByFirstSuspensionInSharedFlow")
end)
