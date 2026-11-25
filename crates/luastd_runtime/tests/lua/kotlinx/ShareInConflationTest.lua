-- kotlin: kotlinx-coroutines-core/common/test/flow/sharing/ShareInConflationTest.kt@1.11.0
local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

describe("ShareInConflationTest", function ()
    local n = 100

    local function check_conflation(capacity, overflow, op, replay)
        -- Eager sharing is scheduled, not undispatched: the active subscriber
        -- observes the first value before the upstream buffer begins dropping.
        local expected = { 0 }
        local first = overflow == "DROP_LATEST" and 1 or n - capacity
        for value = first, first + capacity - 1 do
            if value ~= 0 then expected[#expected + 1] = value end
        end
        local expected_replay = {}
        for i = math.max(1, #expected - replay + 1), #expected do
            if replay > 0 then expected_replay[#expected_replay + 1] = expected[i] end
        end

        local first_emitted = async.channel(0)
        local produced = async.channel(1)
        local done = async.channel(0)
        local completed = async.channel(1)
        local source = flow.new(function (emit)
            for value = 0, n - 1 do
                emit(value)
                if value == 0 then first_emitted:receive() end
            end
            produced:send(true)
            done:receive()
            emit(-1)
            completed:send(true)
        end)
        local shared = op(source):share_in(async.current(), replay)
        local received = {}
        local index = 1
        shared:on_each(function (value)
            if value == 0 then first_emitted:send(true) end
        end):take_while(function (value) return value >= 0 end):collect(function (value)
            assert.is_equal(expected[index], value)
            received[#received + 1] = value
            index = index + 1
            if index > #expected then
                produced:receive()
                assert.same(expected_replay, shared.replay_cache)
                done:send(true)
            end
        end)
        assert.same(expected, received)
        completed:receive()
    end

    -- adapted: rendezvous gates assert surviving values; Lua's scheduled eager
    -- share_in collector receives the first value before the upstream burst.
    it("testConflateReplay1", runtest(function ()
        check_conflation(1, "DROP_OLDEST", function (source) return source:conflate() end, 1)
    end))

    -- adapted: same deterministic gates; the active subscriber sees the
    -- initial value and the final value retained by the upstream buffer.
    it("testConflateReplay0", runtest(function ()
        check_conflation(1, "DROP_OLDEST", function (source) return source:conflate() end, 0)
    end))

    -- adapted: separate upstream conflation and replay buffers do not fuse;
    -- assert the actual first and final conflated values and replay cache.
    it("testConflateReplay5", runtest(function ()
        check_conflation(1, "DROP_OLDEST", function (source) return source:conflate() end, 5)
    end))

    -- adapted: the upstream drop-oldest channel retains the final value and
    -- the shared subscriber verifies that value with replay=1.
    it("testBufferDropOldestReplay1", runtest(function ()
        check_conflation(1, "DROP_OLDEST", function (source) return source:buffer(nil, "DROP_OLDEST") end, 1)
    end))

    -- adapted: the scheduled subscriber also sees the initial value before
    -- the upstream drop-oldest buffer begins retaining its final value.
    it("testBufferDropOldestReplay0", runtest(function ()
        check_conflation(1, "DROP_OLDEST", function (source) return source:buffer(nil, "DROP_OLDEST") end, 0)
    end))

    -- adapted: the upstream buffer remains capacity one beside replay=10;
    -- assert its first/final delivered values and the shorter replay cache.
    it("testBufferDropOldestReplay10", runtest(function ()
        check_conflation(1, "DROP_OLDEST", function (source) return source:buffer(nil, "DROP_OLDEST") end, 10)
    end))

    -- adapted: buffer(20) itself retains the final twenty upstream values;
    -- with replay=0 the active shared subscriber verifies that exact window.
    it("testBuffer20DropOldestReplay0", runtest(function ()
        check_conflation(20, "DROP_OLDEST", function (source) return source:buffer(20, "DROP_OLDEST") end, 0)
    end))

    -- adapted: capacity seven and replay=11 stay separate; assert the first
    -- value plus the seven values retained by the upstream buffer.
    it("testBuffer7DropOldestReplay11", runtest(function ()
        check_conflation(7, "DROP_OLDEST", function (source) return source:buffer(7, "DROP_OLDEST") end, 11)
    end))

    -- adapted: Flow buffer fusion overrides the earlier buffer(23) with the
    -- one-value conflated buffer; assert the surviving shared value.
    it("testBufferConflateOverride", runtest(function ()
        check_conflation(1, "DROP_OLDEST", function (source) return source:buffer(23):conflate() end, 1)
    end))

    -- adapted: the subscriber observes the initial value before the fused
    -- upstream DROP_OLDEST buffer replaces the preceding capacity 23.
    it("testBufferDropOldestOverride", runtest(function ()
        check_conflation(1, "DROP_OLDEST", function (source)
            return source:buffer(23):buffer(nil, "DROP_OLDEST")
        end, 1)
    end))

    -- adapted: upstream DROP_LATEST buffering remains separate from replay;
    -- assert the active subscriber's initial value and retained burst prefix.
    it("testBufferDropLatestReplay0", runtest(function ()
        check_conflation(1, "DROP_LATEST", function (source) return source:buffer(nil, "DROP_LATEST") end, 0)
    end))

    -- adapted: assert the initial subscriber value and the first post-gate
    -- value retained by the separate capacity-one upstream buffer.
    it("testBufferDropLatestReplay1", runtest(function ()
        check_conflation(1, "DROP_LATEST", function (source) return source:buffer(nil, "DROP_LATEST") end, 1)
    end))

    -- adapted: replay does not fuse with the upstream capacity-one buffer.
    it("testBufferDropLatestReplay10", runtest(function ()
        check_conflation(1, "DROP_LATEST", function (source) return source:buffer(nil, "DROP_LATEST") end, 10)
    end))

    -- adapted: capacity zero maps to a one-value DROP_LATEST channel here;
    -- check actual delivery to the subscriber with replay disabled.
    it("testBuffer0DropLatestReplay0", runtest(function ()
        check_conflation(1, "DROP_LATEST", function (source) return source:buffer(0, "DROP_LATEST") end, 0)
    end))

    -- adapted: capacity zero maps to a one-value upstream buffer beside replay.
    it("testBuffer0DropLatestReplay1", runtest(function ()
        check_conflation(1, "DROP_LATEST", function (source) return source:buffer(0, "DROP_LATEST") end, 1)
    end))

    -- adapted: replay=10 remains separate from the one-value upstream buffer.
    it("testBuffer0DropLatestReplay10", runtest(function ()
        check_conflation(1, "DROP_LATEST", function (source) return source:buffer(0, "DROP_LATEST") end, 10)
    end))

    -- adapted: assert initial delivery plus the five-value upstream prefix;
    -- the current share_in runtime does not fuse buffer capacity with replay.
    it("testBuffer5DropLatestReplay0", runtest(function ()
        check_conflation(5, "DROP_LATEST", function (source) return source:buffer(5, "DROP_LATEST") end, 0)
    end))

    -- adapted: replay=10 remains separate from the five-value upstream buffer.
    it("testBuffer5DropLatestReplay10", runtest(function ()
        check_conflation(5, "DROP_LATEST", function (source) return source:buffer(5, "DROP_LATEST") end, 10)
    end))

    -- adapted: the override limits the upstream channel to one value, while
    -- the scheduled subscriber still sees its initial value.
    it("testBufferDropLatestOverride", runtest(function ()
        check_conflation(1, "DROP_LATEST", function (source)
            return source:buffer(23):buffer(nil, "DROP_LATEST")
        end, 0)
    end))
end)
