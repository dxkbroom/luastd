-- Port of kotlinx.coroutines' TransformWhileTest.

local async = require("luastd.async")
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/TransformWhileTest.kt@1.11.0
describe("TransformWhileTest", function ()
    it(
        "testSimple",
        runtest(function ()
            local r = flow.from({ 0, 1, 2, 3, 4 }):transform_while(function (emit, v)
                if v == 0 then
                    emit("A")
                    return true
                end
                if v == 1 then return true end
                if v == 2 then
                    emit("B")
                    emit("C")
                    return true
                end
                if v == 3 then
                    emit("D")
                    return false
                end
                error("unreachable value")
            end):to_list()
            assert.same({ "A", "B", "C", "D" }, r)
        end)
    )

    -- adapted: a rendezvous channel ensures the structured child starts before
    -- the transform stops upstream; its cancellation hook verifies cleanup.
    it(
        "testCancelUpstream",
        runtest(function (t)
            local latch = async.channel(0)
            local source = flow.new(function (emit)
                async.scope(function (scope)
                    local child = scope:launch(function ()
                        t:expect(3)
                        latch:send(true)
                        async.delay(math.huge)
                    end)
                    child:on_cancel(function () t:expect(6) end)
                    t:expect(2)
                    emit(1)
                    emit(2)
                    emit(3)
                end)
            end)

            t:expect(1)
            local r = source:transform_while(function (emit, value)
                if value == 1 then
                    latch:receive()
                    t:expect(4)
                    emit(value)
                    return true
                end
                t:expect(5)
                emit(value)
                return false
            end):to_list()
            assert.same({ 1, 2 }, r)
            t:finish(7)
        end)
    )

    it(
        "testExample",
        runtest(function ()
            local source = { 0, 50, 100, 147 }
            local r = flow.from(source):transform_while(function (emit, percent)
                emit(percent)
                return percent < 100
            end):to_list()
            assert.same({ 0, 50, 100 }, r)
        end)
    )
end)
