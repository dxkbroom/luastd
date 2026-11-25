-- Port of kotlinx.coroutines' MapTest.
local async = require("luastd.async")
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/MapTest.kt@1.11.0
describe("MapTest", function ()
    it("testMap", runtest(function ()
        local result = flow.from({ 1, 2 }):map(function (value) return value + 1 end)
            :fold(0, function (acc, value) return acc + value end)
        assert.is_equal(5, result)
    end))

    it("testEmptyFlow", runtest(function (t)
        local result = flow.empty():map(function () t:expect_unreached() end)
            :fold(0, function (acc, value) return acc + value end)
        assert.is_equal(0, result)
    end))

    -- adapted: use async.scope and a child cancellation hook to observe the
    -- upstream child cleanup while catch emits the replacement value.
    it("testErrorCancelsUpstream", runtest(function ()
        local cancelled = false
        local latch = async.channel(0)
        local failure = luastd_test.TestException()
        local source = flow.new(function (emit)
            async.scope(function (scope)
                local child = scope:launch(function ()
                    latch:send(true)
                    async.delay(math.huge)
                end)
                child:on_cancel(function () cancelled = true end)
                emit(1)
                t:expect_unreached()
            end)
        end):map(function ()
            latch:receive()
            error(failure, 0)
        end):catch(function (emit, err)
            assert.is_true(rawequal(failure, err))
            emit(42)
        end)

        assert.is_equal(42, source:single())
        assert.is_true(cancelled)
    end))
end)
