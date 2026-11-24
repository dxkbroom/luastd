-- kotlin: kotlinx-coroutines-core/common/test/channels/ChannelBufferOverflowTest.kt@1.11.0
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("ChannelBufferOverflowTest", function ()
    -- adapted: try_receive returns a boolean/value/error tuple instead of a
    -- ChannelResult; the buffered values and drop policy are unchanged.
    it(
        "testDropLatest",
        runtest(function ()
            local channel = async.channel(2, "drop_latest")
            assert.is_true(channel:try_send(1))
            assert.is_true(channel:try_send(2))
            assert.is_true(channel:try_send(3))
            channel:send(4) -- overflows and is dropped
            assert.is_equal(1, channel:receive())
            assert.is_true(channel:try_send(5))
            assert.is_true(channel:try_send(6))
            assert.is_equal(2, channel:receive())
            assert.is_equal(5, channel:receive())
            local ok = channel:try_receive()
            assert.is_false(ok)
        end)
    )

    -- adapted: try_receive returns a boolean/value/error tuple instead of a
    -- ChannelResult; the buffered values and drop policy are unchanged.
    it(
        "testDropOldest",
        runtest(function ()
            local channel = async.channel(2, "drop_oldest")
            assert.is_true(channel:try_send(1))
            assert.is_true(channel:try_send(2))
            assert.is_true(channel:try_send(3))
            channel:send(4) -- overflows, keeping 3 and 4
            assert.is_equal(3, channel:receive())
            assert.is_true(channel:try_send(5))
            assert.is_true(channel:try_send(6))
            assert.is_equal(5, channel:receive())
            assert.is_equal(6, channel:receive())
            local ok = channel:try_receive()
            assert.is_false(ok)
        end)
    )
end)
