-- kotlin: kotlinx-coroutines-core/common/test/channels/ChannelFactoryTest.kt@1.11.0
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")

---@param body async fun(t: luastd_test.OrderedExecution, scope: luastd.async.Scope)
---@return fun()
local function run_test(body)
    return luastd_test.runtest(body)
end

describe("ChannelFactoryTest", function ()
    -- adapted: Lua cannot assert Kotlin's internal channel implementation type;
    -- testRendezvousChannel checks the same blocking-send behavior instead.
    it(
        "testRendezvousChannel",
        run_test(function ()
            local channel = async.channel(async.RENDEZVOUS)
            local sent = false
            local sender = async.launch(function ()
                channel:send(1)
                sent = true
            end)
            async.yield()
            assert.is_false(sent)
            assert.is_equal(1, channel:receive())
            async.join(sender)
            assert.is_true(sent)
        end)
    )

    -- adapted: checks unbounded buffering semantics instead of Kotlin's
    -- internal BufferedChannel implementation type.
    it(
        "testUnlimitedChannel",
        run_test(function ()
            for _, overflow in ipairs({ "suspend", "drop_oldest", "drop_latest" }) do
                local channel = async.channel(async.UNLIMITED, overflow)
                for i = 1, 100 do
                    assert.is_true(channel:try_send(i))
                end
                for i = 1, 100 do
                    assert.is_equal(i, channel:receive())
                end
            end
        end)
    )

    -- adapted: checks latest-value conflation instead of Kotlin's internal
    -- ConflatedBufferedChannel implementation type.
    it(
        "testConflatedChannel",
        run_test(function ()
            local conflated = async.channel(async.CONFLATED)
            assert.is_true(conflated:try_send(1))
            assert.is_true(conflated:try_send(2))
            assert.is_equal(2, conflated:receive())

            local drop_oldest = async.channel(1, "drop_oldest")
            assert.is_true(drop_oldest:try_send(1))
            assert.is_true(drop_oldest:try_send(2))
            assert.is_equal(2, drop_oldest:receive())
        end)
    )

    -- adapted: checks requested capacities behaviorally instead of asserting
    -- Kotlin's internal channel implementation types.
    it(
        "testBufferedChannel",
        run_test(function ()
            for _, cap in ipairs({ 1, 10 }) do
                local channel = async.channel(cap)
                assert.is_true(channel:try_send(42))
                assert.is_equal(42, channel:receive())
            end

            local drop_latest = async.channel(1, "drop_latest")
            assert.is_true(drop_latest:try_send(1))
            assert.is_true(drop_latest:try_send(2))
            assert.is_equal(1, drop_latest:receive())
        end)
    )

    it(
        "testInvalidCapacityNotSupported",
        run_test(function ()
            local ok, err = pcall(function () async.channel(-3) end)
            assert.is_false(ok)
            assert.is_equal("InvalidArgument", err.kind)
        end)
    )

    it(
        "testUnsupportedBufferOverflow",
        run_test(function ()
            for _, mode in ipairs({ "drop_oldest", "drop_latest" }) do
                local ok = pcall(function () async.channel(async.CONFLATED, mode) end)
                assert.is_false(ok)
            end
        end)
    )
end)
