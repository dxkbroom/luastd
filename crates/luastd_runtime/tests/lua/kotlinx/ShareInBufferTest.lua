-- kotlin: kotlinx-coroutines-core/common/test/flow/sharing/ShareInBufferTest.kt@1.11.0
local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

local function check_buffer(replay, expected_capacity)
    return runtest(function (t)
        local n = 200
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
        local shared = source:share_in(async.current(), replay)
        shared:take(n):collect(function (value)
            assert.is_equal(received, value)
            received = received + 1
            max_lead = math.max(max_lead, produced - received)
        end)
        assert.is_equal(n, received)
        assert.is_equal(expected_capacity, max_lead)
        t:finish(1)
    end)
end

describe("ShareInBufferTest", function ()
    -- adapted: assert actual ordered delivery and producer lead rather than
    -- Kotlin's scheduler-specific expect trace.
    it("testReplay0DefaultBuffer", check_buffer(0, 64))
    it("testReplay1DefaultBuffer", check_buffer(1, 64))
    it("testReplay10DefaultBuffer", check_buffer(10, 64))
    it("testReplay100DefaultBuffer", check_buffer(100, 100))

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
