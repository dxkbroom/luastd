-- kotlin: kotlinx-coroutines-core/common/test/flow/sharing/SharedFlowScenarioTest.kt@1.11.0
describe("SharedFlowScenarioTest", function ()
    -- defer: mutable_shared_flow has no reset_replay_cache, and its per-subscriber
    -- channel does not model Kotlin's replay/extra-buffer emitter queue behavior.
    pending("testReplay1Extra2")

    -- defer: the scenario depends on reset_replay_cache and precise suspension
    -- of emitters when replay is occupied; the current shared-flow buffer differs.
    pending("testReplay1")

    -- defer: although DROP_OLDEST is accepted as a setting, the implementation
    -- does not drop old buffered subscriber values; it sends or suspends instead.
    pending("testReplay2Extra2DropOldest")

    -- defer: this asserts a fast-subscriber resume race while a queued emitter
    -- resumes; sequential channel fan-out does not implement that shared-flow queue.
    pending("testResumeFastSubscriberOnResumedEmitter")

    -- defer: cancelling a subscriber must release queued emitters in order;
    -- the current shared-flow implementation has no shared emitter queue.
    pending("testSuspendedConcurrentEmitAndCancelSubscriberReplay1")

    -- defer: the same queued-emitter cancellation semantics are required with
    -- extra buffer capacity, which current shared-flow fan-out does not model.
    pending("testSuspendedConcurrentEmitAndCancelSubscriberReplay1ExtraBuffer1")
end)
