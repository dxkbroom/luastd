-- kotlin: kotlinx-coroutines-core/common/test/flow/sharing/ShareInConflationTest.kt@1.11.0
describe("ShareInConflationTest", function ()
    -- defer: Flow:conflate is a no-op synchronously and share_in is absent, so
    -- replay=1 cannot exercise conflated delivery through an eager shared flow.
    pending("testConflateReplay1")

    -- defer: mutable_shared_flow supports replay=0, but there is no share_in
    -- builder or backpressured conflation for the first subscriber.
    pending("testConflateReplay0")

    -- defer: there is no share_in fusion to combine conflation with replay=5
    -- and verify the batch of the latest buffered values.
    pending("testConflateReplay5")

    -- defer: buffer overflow mode is configurable on mutable_shared_flow, but
    -- there is no upstream DROP_OLDEST buffer fused into share_in with replay=1.
    pending("testBufferDropOldestReplay1")

    -- defer: no share_in builder exists to combine upstream DROP_OLDEST with
    -- replay=0 and assert the first subscriber's delivery capacity.
    pending("testBufferDropOldestReplay0")

    -- defer: replay=10 can be set on mutable_shared_flow, but upstream buffer
    -- fusion into an eagerly collected shared flow is unsupported.
    pending("testBufferDropOldestReplay10")

    -- defer: Flow:buffer has no overflow-mode argument and share_in is absent,
    -- so buffer(20) plus replay=0 cannot be checked as one shared capacity.
    pending("testBuffer20DropOldestReplay0")

    -- defer: Flow:buffer has no overflow-mode argument and share_in is absent,
    -- so buffer(7) plus replay=11 cannot be tested as a fused capacity of 18.
    pending("testBuffer7DropOldestReplay11")

    -- defer: Flow:conflate is a no-op and there is no share_in fusion to prove
    -- that conflate overrides a preceding buffer(23).
    pending("testBufferConflateOverride")

    -- defer: Flow:buffer cannot set DROP_OLDEST and there is no share_in fusion
    -- to verify that the overflow buffer overrides buffer(23).
    pending("testBufferDropOldestOverride")

    -- defer: DROP_LATEST exists for mutable_shared_flow, but no share_in builder
    -- can apply an upstream dropping buffer with replay=0.
    pending("testBufferDropLatestReplay0")

    -- defer: there is no share_in fusion to apply upstream DROP_LATEST with
    -- replay=1 and check which values the active subscriber receives.
    pending("testBufferDropLatestReplay1")

    -- defer: replay=10 exists for mutable_shared_flow, but upstream
    -- DROP_LATEST buffering during share_in is not implemented.
    pending("testBufferDropLatestReplay10")

    -- defer: Flow:buffer does not accept an overflow mode and share_in is
    -- absent, so buffer(0)/DROP_LATEST/replay=0 cannot be represented.
    pending("testBuffer0DropLatestReplay0")

    -- defer: Flow:buffer does not accept an overflow mode and share_in is
    -- absent, so buffer(0)/DROP_LATEST/replay=1 cannot be represented.
    pending("testBuffer0DropLatestReplay1")

    -- defer: Flow:buffer does not accept an overflow mode and share_in is
    -- absent, so buffer(0)/DROP_LATEST/replay=10 cannot be represented.
    pending("testBuffer0DropLatestReplay10")

    -- defer: there is no share_in fusion to combine buffer(5), DROP_LATEST,
    -- and replay=0 into the tested effective capacity.
    pending("testBuffer5DropLatestReplay0")

    -- defer: there is no share_in fusion to combine buffer(5), replay=10, and
    -- DROP_LATEST while preserving the total capacity of 15.
    pending("testBuffer5DropLatestReplay10")

    -- defer: Flow:buffer cannot select DROP_LATEST and there is no share_in
    -- fusion to verify that it overrides the preceding buffer(23).
    pending("testBufferDropLatestOverride")
end)
