-- Port of kotlinx.coroutines' OnEachTest.

local async = require("luastd.async")
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/OnEachTest.kt@1.11.0
describe("OnEachTest", function ()
    it(
        "testOnEach",
        runtest(function (t)
            local seen = {}
            local result = flow.from({ 1, 2 }):on_each(function (value)
                t:expect(value)
                seen[#seen + 1] = value
            end):to_list()
            assert.same({ 1, 2 }, result)
            assert.same({ 1, 2 }, seen)
            t:finish(3)
        end)
    )

    -- adapted: no single_or_null terminal exists; an empty result list
    -- represents Kotlin's null result for an empty flow.
    it(
        "testEmptyFlow",
        runtest(function ()
            local result = flow.empty():on_each(function () end):to_list()
            assert.is_equal(0, #result)
        end)
    )

    -- adapted: this uses the structured-scope cancellation hook from FoldTest
    -- but verifies the error path through on_each and catch specifically.
    it(
        "testErrorCancelsUpstream",
        runtest(function (t)
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
            local recovered = source:on_each(function ()
                latch:receive()
                t:expect(4)
                error(failure, 0)
            end):catch(function (emit, err)
                assert.is_true(rawequal(failure, err))
                t:expect(6)
                emit(42)
            end):single()
            assert.is_equal(42, recovered)
            t:finish(7)
        end)
    )
end)
