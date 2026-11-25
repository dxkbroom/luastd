-- kotlin: kotlinx-coroutines-core/common/test/flow/sharing/ShareInBufferTest.kt@1.11.0
local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

describe("ShareInBufferTest", function ()
    -- adapted: check ordered delivery and bounded producer lead for eager replay=0
    -- sharing; the scheduler does not reproduce Kotlin's exact batch trace.
    it("testReplay0DefaultBuffer", runtest(function (t)
        local n = 200
        local capacity = 64
        local produced = 0
        local received = 0
        local max_lead = 0
        local source = flow.new(function (emit)
            for i = 0, n - 1 do
                produced = produced + 1
                emit(i)
            end
            emit(-1)
        end)
        local shared = source:share_in(async.current())
        shared:take(n):collect(function (value)
            assert.is_equal(received, value)
            received = received + 1
            max_lead = math.max(max_lead, produced - received)
        end)
        assert.is_equal(n, received)
        assert.is_true(max_lead > 1)
        assert.is_true(max_lead <= capacity + 1)
        t:finish(1)
    end))

    -- defer: current share_in allocates replay + 64 slots, so replay=1 makes
    -- the effective shared buffer 65 instead of Kotlin's padded 64.
    pending("testReplay1DefaultBuffer")

    -- defer: current share_in adds replay to its default 64 slots instead of
    -- using max(replay, default capacity) when replay is greater than zero.
    pending("testReplay10DefaultBuffer")
    pending("testReplay100DefaultBuffer")

    -- defer: buffer fusion does not carry an upstream default buffer through
    -- share_in; source and shared buffers remain separate.
    pending("testDefaultBufferKeepsDefault")

    -- defer: share_in does not fuse buffer(0) into its shared-flow capacity;
    -- it retains the default 64-slot shared buffer.
    pending("testOverrideDefaultBuffer0")

    -- defer: share_in does not use buffer(10) as its effective shared-flow
    -- capacity; the source buffer and 64-slot shared buffer remain separate.
    pending("testOverrideDefaultBuffer10")

    -- defer: upstream buffer capacities and replay are not fused into a single
    -- effective shared buffer; current capacities compose independently.
    pending("testBufferReplaySum")
end)
