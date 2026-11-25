-- kotlin: kotlinx-coroutines-core/common/test/channels/ChannelIteratorTest.kt@1.11.0
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("ChannelIteratorTest", function ()
    -- adapted: luastd exposes an iterator closure rather than Kotlin's
    -- hasNext()/next() iterator object.
    it(
        "testIteratorClosedHasNextFalse",
        runtest(function ()
            local channel = async.channel()
            channel:close()
            local next = channel:iter()
            assert.is_nil(next())
        end)
    )

    -- adapted: closing with a cause is observed by invoking the iterator
    -- closure rather than hasNext().
    it(
        "testIteratorClosedWithExceptionHasNextThrows",
        runtest(function ()
            local channel = async.channel()
            local cause = luastd_test.TestException("closed")
            channel:close(cause)
            local ok, err = pcall(channel:iter())
            assert.is_false(ok)
            assert.is_true(cause == err)
        end)
    )
end)
