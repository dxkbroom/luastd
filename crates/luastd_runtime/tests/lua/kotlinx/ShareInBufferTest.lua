-- kotlin: kotlinx-coroutines-core/common/test/flow/sharing/ShareInBufferTest.kt@1.11.0
describe("ShareInBufferTest", function ()
    -- defer: luastd has replayable mutable_shared_flow but no share_in operator
    -- that launches this cold upstream with an eager sharing strategy and default
    -- buffer capacity.
    pending("testReplay0DefaultBuffer")

    -- defer: there is no share_in builder to combine replay=1 with the default
    -- sharing buffer and test its backpressure batch size.
    pending("testReplay1DefaultBuffer")

    -- defer: share_in is absent, so replay=10 cannot be checked for padding to
    -- the default buffer capacity during active sharing.
    pending("testReplay10DefaultBuffer")

    -- defer: share_in is absent, so replay=100 cannot be tested against the
    -- max(replay, default capacity) shared buffer.
    pending("testReplay100DefaultBuffer")

    -- defer: Flow:buffer exists, but there is no share_in operation with which
    -- to verify that a default upstream buffer preserves the sharing default.
    pending("testDefaultBufferKeepsDefault")

    -- defer: there is no sharing builder to combine buffer(0) with replay=0
    -- and test true rendezvous backpressure across subscribers.
    pending("testOverrideDefaultBuffer0")

    -- defer: buffer(10) exists, but share_in is missing, so its capacity cannot
    -- be tested as the effective shared-flow buffer.
    pending("testOverrideDefaultBuffer10")

    -- defer: Flow:buffer can compose capacities, but there is no share_in
    -- operation to add replay capacity and verify the resulting shared buffer.
    pending("testBufferReplaySum")
end)
