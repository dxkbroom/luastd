-- kotlin: kotlinx-coroutines-core/common/test/channels/UnlimitedChannelTest.kt@1.11.0
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("UnlimitedChannelTest", function ()
    -- adapted: try_receive returns a boolean/value/error tuple instead of a
    -- ChannelResult; ordering and unlimited buffering remain the same.
    it(
        "testBasic",
        runtest(function ()
            local channel = async.channel(async.UNLIMITED)
            channel:send(1)
            assert.is_true(channel:try_send(2))
            channel:send(3)
            channel:close()
            assert.is_equal(1, channel:receive())
            local ok, value = channel:try_receive()
            assert.is_true(ok)
            assert.is_equal(2, value)
            assert.is_equal(3, channel:receive())
            local closed_ok, _, close_err = channel:try_receive()
            assert.is_false(closed_ok)
            assert.is_equal("ChannelClosed", close_err.kind)
        end)
    )

    -- defer: receiveCatching must expose cancellation as CancellationException;
    -- luastd cancellation cannot be caught (ADR 0005).
    pending("testConsumeAll")

    -- defer: Channel.cancel(cause) is not supported.
    pending("testCancelWithCause")
end)
