-- Port of kotlinx.coroutines' DropTest.

local async = require("luastd.async")
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/DropTest.kt@1.11.0
describe("DropTest", function ()
    -- adapted: there is no single_or_null terminal; assert the large drop through an empty list.
    it("testDrop", runtest(function ()
        local source = flow.from({ 1, 2, 3 })
        local dropped = source:drop(1):to_list()
        assert.same({ 2, 3 }, dropped)
        assert.is_equal(5, dropped[1] + dropped[2])
        assert.same({}, source:drop(2147483647):to_list())
        assert.is_equal(3, source:drop(1):take(2):drop(1):single())
    end))

    it("testEmptyFlow", runtest(function ()
        local r = flow.empty():drop(2):to_list()
        assert.is_equal(0, #r)
    end))

    -- adapted: Kotlin throws IllegalArgumentException; luastd reports structured InvalidArgument.
    it("testNegativeCount", runtest(function ()
        for _, count in ipairs({ -1, 1.5 }) do
            local ok, err = pcall(function () flow.empty():drop(count) end)
            assert.is_false(ok)
            assert.is_equal("InvalidArgument", err.kind)
        end
    end))

    -- adapted: a rendezvous latch yields to the structured child before the
    -- second value reaches map; the mapper error cancels upstream before catch recovers.
    it("testErrorCancelsUpstream", runtest(function (t)
        local latch = async.channel(0)
        local failure = luastd_test.TestException()
        local source = flow.new(function (emit)
            async.scope(function (scope)
                local child = scope:launch(function ()
                    latch:send(true)
                    async.await_cancellation()
                end)
                child:on_cancel(function () t:expect(5) end)
                t:expect(2)
                emit(1)
                t:expect(3)
                emit(2)
            end)
        end)

        t:expect(1)
        local result = source:drop(1):map(function ()
            latch:receive()
            t:expect(4)
            error(failure, 0)
        end):catch(function (emit, err)
            assert.is_true(rawequal(failure, err))
            emit(42)
        end):single()
        assert.is_equal(42, result)
        t:finish(6)
    end))
end)
