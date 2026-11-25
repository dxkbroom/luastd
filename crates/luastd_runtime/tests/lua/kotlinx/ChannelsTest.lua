-- Port of kotlinx.coroutines' ChannelsTest.
-- luastd has no `asReceiveChannel`, `toList` or `consumeTo` helpers, and
-- `produce` and `each` stand in for them.
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

--- A channel that sends `items` and then closes, like `Iterable.asReceiveChannel`.
---@param items any[]
---@return luastd.async.Channel
local function receive_channel(items)
    return async.produce(function (channel)
        for _, item in ipairs(items) do
            channel:send(item)
        end
    end)
end

--- The error `fn` raised, as a `luastd.Error`.
---@param fn fun()
---@return any
local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return err
end

-- kotlin: kotlinx-coroutines-core/common/test/channels/ChannelsTest.kt@1.11.0
describe("ChannelsTest", function ()
    it(
        "testIterableAsReceiveChannel",
        runtest(function ()
            -- adapted: produced from the list instead of an `asReceiveChannel`
            -- extension.
            local result = {}
            for x in receive_channel({ 1, 2, 3 }):iter() do
                result[#result + 1] = x
            end
            assert.same({ 1, 2, 3 }, result)
        end)
    )

    it(
        "testCloseWithMultipleSuspendedReceivers",
        runtest(function (t)
            local channel = async.channel()
            t:expect(1)
            async.launch(function ()
                t:expect(2)
                local err = error_of(function () channel:receive() end)
                t:expect(5)
                assert.is_equal("ChannelClosed", err.kind)
            end)
            async.launch(function ()
                t:expect(3)
                local err = error_of(function () channel:receive() end)
                t:expect(6)
                assert.is_equal("ChannelClosed", err.kind)
            end)
            async.yield()
            t:expect(4)
            channel:close()
            async.yield()
            t:finish(7)
        end)
    )

    it(
        "testCloseWithMultipleSuspendedSenders",
        runtest(function (t)
            -- adapted: cancellation is not catchable (ADR 0005), so the
            -- suspended senders end cancelled instead of entering a catch.
            local channel = async.channel()
            t:expect(1)
            local first = async.launch(function ()
                t:expect(2)
                channel:send(42)
                t:expect_unreached()
            end)
            local second = async.launch(function ()
                t:expect(3)
                channel:send(42)
                t:expect_unreached()
            end)
            async.yield()
            t:expect(4)
            channel:cancel()
            async.yield()
            assert.is_true(first:is_cancelled())
            assert.is_true(second:is_cancelled())
            t:finish(5)
        end)
    )

    it(
        "testEmptyToList",
        runtest(function ()
            -- adapted: collected from an empty produced channel, no `toList`.
            local result = {}
            for x in receive_channel({}):iter() do
                result[#result + 1] = x
            end
            assert.is_equal(0, #result)
        end)
    )

    it(
        "testToList",
        runtest(function ()
            -- adapted: collected from a produced channel, no `toList`.
            local result = {}
            for x in receive_channel({ 1, 2, 3 }):iter() do
                result[#result + 1] = x
            end
            assert.same({ 1, 2, 3 }, result)
        end)
    )

    it(
        "testToListOnFailedChannel",
        runtest(function ()
            local channel = async.channel(2)
            channel:send(1)
            local cause = luastd_test.TestException("boom")
            channel:close(cause)
            local result = {}
            local ok, err = pcall(function ()
                for x in channel:iter() do
                    result[#result + 1] = x
                end
            end)
            assert.is_false(ok)
            assert.is_true(cause == err)
            assert.are.same({ 1 }, result)
        end)
    )

    it(
        "testEmptyConsumeToWithDestination",
        runtest(function ()
            -- adapted: `each` appends to the destination, no `consumeTo`.
            local destination = { -1, -2, -3 }
            receive_channel({}):each(function (x)
                destination[#destination + 1] = x
            end)
            assert.same({ -1, -2, -3 }, destination)
        end)
    )

    it(
        "testConsumeToWithDestination",
        runtest(function ()
            -- adapted: `each` appends to the destination, no `consumeTo`.
            local destination = { -1, -2, -3 }
            receive_channel({ 1, 2, 3 }):each(function (x)
                destination[#destination + 1] = x
            end)
            assert.same({ -1, -2, -3, 1, 2, 3 }, destination)
        end)
    )

    it(
        "testConsumeToWithDestinationOnFailedChannel",
        runtest(function ()
            local destination = { -1 }
            local channel = async.channel(1)
            channel:send(1)
            local cause = luastd_test.TestException("boom")
            channel:close(cause)
            local ok, err = pcall(function ()
                channel:each(function (x) destination[#destination + 1] = x end)
            end)
            assert.is_false(ok)
            assert.is_true(cause == err)
            assert.are.same({ -1, 1 }, destination)
        end)
    )
end)
