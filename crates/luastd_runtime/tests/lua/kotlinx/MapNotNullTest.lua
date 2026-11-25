-- Port of kotlinx.coroutines' MapNotNullTest.

local async = require("luastd.async")
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/MapNotNullTest.kt@1.11.0
describe("MapNotNullTest", function ()
    it(
        "testMap",
        runtest(function ()
            local source = flow.new(function (emit)
                emit(1)
                emit(nil)
                emit(2)
            end)
            local result = source:map_not_null(function (value) return value end):to_list()
            assert.same({ 1, 2 }, result)
        end)
    )

    it(
        "testEmptyFlow",
        runtest(function ()
            local r = flow.empty():map_not_null(function (x) return x end):to_list()
            assert.is_equal(0, #r)
        end)
    )

    -- adapted: use a rendezvous channel and child cancellation hook to preserve
    -- the upstream cleanup assertion; `single` replaces Kotlin's `sum` because
    -- the recovered stream contains only the one value 42.
    it("testErrorCancelsUpstream", runtest(function (t)
        local latch = async.channel(0)
        local failure = luastd_test.TestException()
        local source = flow.new(function (emit)
            async.scope(function (scope)
                local child = scope:launch(function ()
                    t:expect(3)
                    latch:send(true)
                    async.delay(math.huge)
                end)
                child:on_cancel(function () t:expect(5) end)
                t:expect(2)
                emit(1)
            end)
        end)

        t:expect(1)
        local recovered = source:map_not_null(function (value)
            latch:receive()
            assert.is_equal(1, value)
            t:expect(4)
            error(failure, 0)
        end):catch(function (emit, err)
            assert.is_true(rawequal(failure, err))
            t:expect(6)
            emit(42)
        end):single()
        assert.is_equal(42, recovered)
        t:finish(7)
    end))
end)
