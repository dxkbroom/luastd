-- kotlin: kotlinx-coroutines-core/common/test/channels/ChannelReceiveCatchingTest.kt@1.11.0
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("ChannelReceiveCatchingTest", function ()
    -- adapted: ChannelResult is unavailable; receive returns the value and
    -- raises the close cause directly.
    it(
        "testChannelOfThrowables",
        runtest(function ()
            local channel = async.channel()
            local cause = luastd_test.TestException("second")
            local first = luastd_test.TestException("first")
            local sender = async.launch(function ()
                channel:send(first)
                channel:close(cause)
            end)
            assert.is_true(first == channel:receive())
            async.join(sender)
            local ok, err = pcall(function () channel:receive() end)
            assert.is_false(ok)
            assert.is_true(cause == err)
        end)
    )

    -- defer: channels reject nil values; Kotlin's nullable-element case depends
    -- on ChannelResult preserving a sent null separately from closure.
    pending("testNullableIntChanel")

    -- adapted: Lua uses integers directly instead of a UInt wrapper.
    it(
        "testUIntChannel",
        runtest(function (t)
            local channel = async.channel()
            local sender = async.launch(function ()
                t:expect(2)
                channel:send(1)
                async.yield()
                t:expect(4)
                channel:send(4294967294)
                t:expect(5)
            end)
            t:expect(1)
            assert.is_equal(1, channel:receive())
            t:expect(3)
            assert.is_equal(4294967294, channel:receive())
            async.join(sender)
            t:finish(6)
        end)
    )

    -- defer: cancellation is uncatchable in luastd; there is no
    -- receiveCatching result to inspect after channel cancellation.
    pending("testCancelChannel")

    -- defer: luastd has no ChannelResult value to send or inspect.
    pending("testReceiveResultChannel")

    -- defer: luastd has no ChannelResult string representation.
    pending("testToString")
end)
