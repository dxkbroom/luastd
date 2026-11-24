-- kotlin: kotlinx-coroutines-core/common/test/channels/ProduceConsumeTest.kt@1.11.0
local async = require("luastd.async")
local runtest = require("luastd_test").runtest

local function test_producer(messages, capacity)
    local sent_all = false
    local producer = async.produce(function (channel)
        for value = 1, messages do channel:send(value) end
        sent_all = true
    end, capacity)
    local consumed = 0
    for _ in producer:iter() do consumed = consumed + 1 end
    assert.is_true(sent_all)
    assert.is_equal(messages, consumed)
end

describe("ProduceConsumeTest", function ()
    it("testRendezvous", runtest(function ()
        test_producer(1, async.RENDEZVOUS)
        test_producer(10, async.RENDEZVOUS)
        test_producer(100, async.RENDEZVOUS)
    end))

    it("testSmallBuffer", runtest(function ()
        test_producer(1, 1)
        test_producer(10, 1)
        test_producer(100, 1)
    end))

    it("testMediumBuffer", runtest(function ()
        test_producer(1, 10)
        test_producer(10, 10)
        test_producer(100, 10)
    end))

    it("testLargeMediumBuffer", runtest(function ()
        test_producer(1, 1000)
        test_producer(10, 1000)
        test_producer(100, 1000)
    end))

    it("testUnlimited", runtest(function ()
        test_producer(1, async.UNLIMITED)
        test_producer(10, async.UNLIMITED)
        test_producer(100, async.UNLIMITED)
    end))
end)
