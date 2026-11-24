-- kotlin: kotlinx-coroutines-core/common/test/channels/ConsumeTest.kt@1.11.0
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("ConsumeTest", function ()
    -- not-applicable: this regression test exercises a Kotlin/JS compiler bug
    -- in ReceiveChannel.consume, which has no Lua runtime equivalent.
    pending("testConsumeJsMiscompilation")

    -- adapted: Channel:each is the available consuming operation and cancels
    -- on exit; close first because an open empty channel would suspend.
    it(
        "testConsumeClosesOnSuccess",
        runtest(function ()
            local channel = async.channel()
            channel:close()
            channel:each(function () error("unreached") end)
            assert.is_true(channel:is_closed_for_receive())
        end)
    )

    -- adapted: Channel:each cancels the channel in its cleanup after the
    -- callback error, matching the externally visible closed state.
    it(
        "testConsumeClosesOnFailure",
        runtest(function ()
            local channel = async.channel(1)
            local failure = luastd_test.TestException()
            channel:send(1)
            local ok, err = pcall(function () channel:each(function () error(failure, 0) end) end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
            assert.is_true(channel:is_closed_for_receive())
        end)
    )

    -- adapted: a callback returning false is Channel:each's early-stop form;
    -- it cancels the channel before returning.
    it(
        "testConsumeClosesOnEarlyReturn",
        runtest(function ()
            local channel = async.channel(1)
            channel:send(1)
            channel:each(function () return false end)
            assert.is_true(channel:is_closed_for_receive())
        end)
    )

    it(
        "testConsumeEachClosesOnSuccess",
        runtest(function ()
            local channel = async.channel()
            channel:close()
            channel:each(function () error("unreached") end)
            assert.is_true(channel:is_closed_for_receive())
        end)
    )

    it(
        "testConsumeEachClosesOnFailure",
        runtest(function ()
            local channel = async.channel(1)
            local failure = luastd_test.TestException()
            channel:send(1)
            local ok, err = pcall(function () channel:each(function () error(failure, 0) end) end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
            assert.is_true(channel:is_closed_for_receive())
        end)
    )

    -- adapted: returning false is the Channel:each early-exit contract; verify
    -- that it cancels the channel after processing the queued value.
    it(
        "testConsumeEachClosesOnEarlyReturn",
        runtest(function ()
            local channel = async.channel(1)
            channel:send(1)
            channel:each(function () return false end)
            assert.is_true(channel:is_closed_for_receive())
        end)
    )

    -- not-applicable: the Kotlin case depends on cancellation inside a child
    -- scope and an onUndeliveredElement callback; luastd exposes neither.
    pending("testConsumeEachExitsOnCancellation")

    it(
        "testConsumeEachThrowingOnChannelClosing",
        runtest(function ()
            local channel = async.channel()
            local failure = luastd_test.TestException()
            channel:close(failure)
            local ok, err = pcall(function () channel:each(function () error("unreached") end) end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
            assert.is_true(channel:is_closed_for_receive())
        end)
    )

    -- not-applicable: BroadcastChannel.consume is unavailable; luastd exposes
    -- Channel and SharedFlow instead.
    pending("testBroadcastChannelConsumeJsMiscompilation")
end)
