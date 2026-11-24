-- kotlin: kotlinx-coroutines-core/common/test/channels/ChannelPropertiesTest.kt@1.11.0
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("ChannelPropertiesAfterClosingTest", function ()
    it(
        "testClosedIsClosedForReceive",
        runtest(function ()
            local function check(cause)
                for _, capacity in ipairs({ async.RENDEZVOUS, 1, async.UNLIMITED, async.CONFLATED }) do
                    local channel = async.channel(capacity)
                    assert.is_false(channel:is_closed_for_receive())
                    channel:close(cause)
                    assert.is_true(channel:is_closed_for_receive())
                end
            end
            check(nil)
            check(luastd_test.TestException("closed"))
        end)
    )

    it(
        "testClosedIsEmptyFalse",
        runtest(function ()
            local function check(cause)
                for _, capacity in ipairs({ async.RENDEZVOUS, 1, async.UNLIMITED, async.CONFLATED }) do
                    local channel = async.channel(capacity)
                    assert.is_true(channel:is_empty())
                    assert.is_false(channel:is_closed_for_receive())
                    channel:close(cause)
                    assert.is_false(channel:is_empty())
                    assert.is_true(channel:is_closed_for_receive())
                end
            end
            check(nil)
            check(luastd_test.TestException("closed"))
        end)
    )

    it(
        "testSendClosedReceiveIsEmptyFalse",
        runtest(function ()
            local function check(cause)
                local channel = async.channel(1)
                assert.is_true(channel:is_empty())
                assert.is_false(channel:is_closed_for_receive())
                channel:send(1)
                assert.is_false(channel:is_empty())
                assert.is_false(channel:is_closed_for_receive())
                channel:close(cause)
                assert.is_false(channel:is_empty())
                assert.is_false(channel:is_closed_for_receive())
                assert.is_equal(1, channel:receive())
                assert.is_false(channel:is_empty())
                assert.is_true(channel:is_closed_for_receive())
            end
            check(nil)
            check(luastd_test.TestException("closed"))
        end)
    )
end)
