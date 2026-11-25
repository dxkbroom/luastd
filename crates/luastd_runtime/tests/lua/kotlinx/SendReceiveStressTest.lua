-- kotlin: kotlinx-coroutines-core/common/test/channels/SendReceiveStressTest.kt@1.11.0
local async = require("luastd.async")
local runtest = require("luastd_test").runtest

local function stress(channel_capacity)
    return runtest(function ()
        local n = 100
        local channel = async.channel(channel_capacity)
        local received = {}
        local sender = async.launch(function ()
            for i = 1, n do
                channel:send(i)
            end
        end)
        local receiver = async.launch(function ()
            for _ = 1, n do
                received[#received + 1] = channel:receive()
            end
        end)

        async.join(sender)
        async.join(receiver)

        local expected = {}
        for i = 1, n do expected[i] = i end
        assert.same(expected, received)
    end)
end

describe("SendReceiveStressTest", function ()
    it("testBufferedChannel", stress(2))
    it("testUnlimitedChannel", stress(async.UNLIMITED))
    it("testRendezvousChannel", stress(async.RENDEZVOUS))
end)
