-- kotlin: kotlinx-coroutines-core/common/test/channels/BufferedChannelTest.kt@1.11.0
local async = require("luastd.async")
local luastd_test = require("luastd_test")

describe("BufferedChannelTest", function ()
    it("testMemoryConsumption", luastd_test.runtest(function ()
        local channel = async.channel(1000000000)
        for i = 1, 10000 do channel:send(i) end
        for i = 1, 10000 do assert.is_equal(i, channel:receive()) end
    end))

    -- adapted: Lua's iterator is a consuming function, not Kotlin's peekable
    -- iterator object; check that iteration yields each queued value once.
    it("testIteratorHasNextIsIdempotent", luastd_test.runtest(function ()
        local channel = async.channel()
        local sender = async.launch(function ()
            channel:send(1)
            channel:close()
        end)
        local values = {}
        for value in channel:iter() do values[#values + 1] = value end
        async.join(sender)
        assert.same({ 1 }, values)
        assert.is_true(channel:is_closed_for_receive())
    end))

    -- adapted: internal BufferedChannel segment invariants are not exposed;
    -- verify bounded buffering and that a waiting sender progresses in order.
    it("testSimple", luastd_test.runtest(function ()
        local channel = async.channel(1)
        local sender = async.launch(function ()
            channel:send(1)
            channel:send(2)
        end)
        assert.is_equal(1, channel:receive())
        assert.is_equal(2, channel:receive())
        async.join(sender)
        assert.is_true(channel:is_empty())
    end))

    -- adapted: check buffered values drain after close with the public state
    -- queries and try_receive result, instead of internal segment invariants.
    it("testClosedBufferedReceiveCatching", luastd_test.runtest(function (t)
        local channel = async.channel(1)
        local receiver = async.launch(function ()
            t:expect(5)
            assert.is_false(channel:is_closed_for_receive())
            assert.is_equal(42, channel:receive())
            t:expect(6)
            assert.is_true(channel:is_closed_for_receive())
            local ok, value, err = channel:try_receive()
            assert.is_false(ok)
            assert.is_nil(value)
            assert.is_equal("ChannelClosed", err.kind)
            t:expect(7)
        end)
        t:expect(1)
        channel:send(42)
        t:expect(2)
        channel:close()
        t:expect(3)
        assert.is_false(channel:is_closed_for_receive())
        t:expect(4)
        async.yield()
        assert.is_true(channel:is_closed_for_receive())
        async.join(receiver)
        t:finish(8)
    end))

    it("testClosedExceptions", luastd_test.runtest(function (t)
        local channel = async.channel(1)
        local receiver = async.launch(function ()
            t:expect(4)
            local ok, err = pcall(function () channel:receive() end)
            assert.is_false(ok)
            assert.is_equal("ChannelClosed", err.kind)
            t:expect(5)
        end)
        t:expect(1)
        channel:close()
        t:expect(2)
        t:expect(3)
        async.yield()
        local sent, err = channel:try_send(42)
        assert.is_false(sent)
        assert.is_equal("ChannelClosed", err.kind)
        async.join(receiver)
        t:finish(6)
    end))

    it("testTryOp", luastd_test.runtest(function (t)
        local channel = async.channel(1)
        assert.is_true(channel:try_send(1))
        assert.is_false(channel:try_send(2))
        local ok, value = channel:try_receive()
        assert.is_true(ok)
        assert.is_equal(1, value)
        assert.is_false(channel:try_receive())
        assert.is_true(channel:try_send(2))
        assert.is_false(channel:try_send(3))
        assert.is_equal(2, channel:receive())
        assert.is_true(channel:try_send(3))
        assert.is_false(channel:try_send(4))
        assert.is_equal(3, channel:receive())
        assert.is_false(channel:try_receive())
        t:finish(1)
    end))

    -- adapted: launch is cancellable and has no undispatched start option;
    -- queued senders are cancelled after channel cancellation instead.
    it("testConsumeAll", luastd_test.runtest(function (t)
        local channel = async.channel(5)
        local senders = {}
        for i = 1, 5 do
            t:expect(i)
            channel:send(i)
        end
        for i = 6, 10 do
            senders[#senders + 1] = async.launch(function ()
                t:expect(i)
                channel:send(i)
                t:expect_unreached()
            end)
        end
        async.yield()
        t:expect(11)
        channel:cancel()
        assert.is_true(channel:is_closed())
        assert.is_true(channel:is_closed_for_receive())
        for _, sender in ipairs(senders) do async.join(sender) end
        t:finish(12)
    end))

    -- not-applicable: Channel:cancel has no cause parameter; close(cause)
    -- preserves buffered values and therefore does not model cancel(cause).
    pending("testCancelWithCause")

    -- adapted: test the requested capacity through observable send/receive
    -- ordering rather than Kotlin's internal channel segment inspection.
    it("testBufferSize", luastd_test.runtest(function (t)
        local capacity = 42
        local channel = async.channel(capacity)
        local sender = async.launch(function ()
            t:expect(2)
            for i = 0, capacity - 1 do channel:send(i) end
            t:expect(3)
            channel:send(capacity)
            t:expect(5)
            channel:close()
        end)
        t:expect(1)
        async.yield()
        t:expect(4)
        local values = {}
        for value in channel:iter() do values[#values + 1] = value end
        assert.same((function ()
            local expected = {}
            for i = 0, capacity do expected[#expected + 1] = i end
            return expected
        end)(), values)
        async.join(sender)
        t:finish(6)
    end))

    -- adapted: as in testBufferSize, verify the capacity after the channel
    -- has advanced through several send/receive operations.
    it("testBufferSizeFromTheMiddle", luastd_test.runtest(function (t)
        local capacity = 42
        local channel = async.channel(capacity)
        for _ = 1, 4 do assert.is_true(channel:try_send(-1)) end
        for _ = 1, 4 do assert.is_equal(-1, channel:receive()) end
        local sender = async.launch(function ()
            t:expect(2)
            for i = 0, capacity - 1 do channel:send(i) end
            t:expect(3)
            channel:send(capacity)
            t:expect(5)
            channel:close()
        end)
        t:expect(1)
        async.yield()
        t:expect(4)
        local values = {}
        for value in channel:iter() do values[#values + 1] = value end
        assert.is_equal(capacity + 1, #values)
        for i = 0, capacity do assert.is_equal(i, values[i + 1]) end
        async.join(sender)
        t:finish(6)
    end))

    -- not-applicable: Lua exposes capacity behavior, not whether channel
    -- storage was preallocated internally; that allocation detail is opaque.
    pending("testBufferIsNotPreallocated")
end)
