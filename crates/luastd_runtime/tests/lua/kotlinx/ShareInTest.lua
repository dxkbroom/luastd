-- kotlin: kotlinx-coroutines-core/common/test/flow/sharing/ShareInTest.kt@1.11.0
describe("ShareInTest", function ()
    -- defer: mutable_shared_flow can manually retain replay=0, but there is no
    -- share_in operator to eagerly collect a cold source before subscribers join.
    pending("testReplay0Eager")

    -- defer: no share_in or SharingStarted.Lazily policy exists to start the
    -- source on the first subscriber and coordinate subscribers without replay.
    pending("testReplay0Lazy")

    -- defer: the API has no lazy sharing job or subscriber barriers to test
    -- replay=1 delivery across the first and later subscribers.
    pending("testReplay1Lazy")

    -- defer: share_in is absent, so upstream completion cannot be observed
    -- while preserving a shared flow's replay cache.
    pending("testUpstreamCompleted")

    -- defer: there is no sharing job whose completion state and failure can be
    -- observed while the shared replay cache remains available.
    pending("testUpstreamFailed")

    -- defer: the API has no SharingStarted.WhileSubscribed strategy or
    -- subscription count tracking to start and stop upstream work.
    pending("testWhileSubscribedBasic")

    -- defer: there is no custom sharing strategy driven by subscription counts
    -- to enforce a one-subscriber start threshold.
    pending("testWhileSubscribedCustomAtLeast1")

    -- defer: there is no subscription-count flow or sharing strategy to enforce
    -- the custom two-subscriber start/stop threshold.
    pending("testWhileSubscribedCustomAtLeast2")

    -- defer: the API lacks share_in, on_subscription, and lazy sharing startup,
    -- so cancellation from the first subscription cannot test startup ordering.
    pending("testShouldStart")

    -- defer: state_in and lazy SharingStarted policies are absent, so scalar
    -- source startup and initial-state/replayed-state sequencing are unsupported.
    pending("testShouldStartScalar")

    -- defer: state_in and the shared-flow first-suspension subscription
    -- behavior are absent; mutable_shared_flow has no subscription hook.
    pending("testSubscriptionByFirstSuspensionInSharedFlow")
end)
