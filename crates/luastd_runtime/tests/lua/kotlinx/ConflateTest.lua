-- Port of kotlinx.coroutines' ConflateTest.

local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/ConflateTest.kt@1.11.0
describe("ConflateTest", function ()
    -- adapted: rendezvous gates make the producer fill three batches while
    -- collection is delayed; this replaces virtual-time scheduling.
    it(
        "testExample",
        runtest(function (t)
            t:expect(1)
            local first_seen = async.channel(0)
            local tenth_seen = async.channel(0)
            local twentieth_seen = async.channel(0)
            local source = flow.new(function (emit)
                emit(1)
                first_seen:receive()
                for value = 2, 10 do
                    emit(value)
                end
                tenth_seen:receive()
                for value = 11, 20 do
                    emit(value)
                end
                twentieth_seen:receive()
                for value = 21, 30 do
                    emit(value)
                end
            end)

            local result = source:conflate():on_each(function (value)
                if value == 1 then first_seen:send(true) end
                if value == 10 then tenth_seen:send(true) end
                if value == 20 then twentieth_seen:send(true) end
                async.yield()
            end):to_list()
            assert.same({ 1, 10, 20, 30 }, result)
            t:finish(2)
        end)
    )
end)
