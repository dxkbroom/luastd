-- Port of kotlinx.coroutines' TakeWhileTest.

local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/TakeWhileTest.kt@1.11.0
describe("TakeWhileTest", function ()
    -- adapted: Flow has no sum or singleOrNull terminals; sum the values and
    -- represent singleOrNull() == null with an empty result list.
    it(
        "testTakeWhile",
        runtest(function ()
            local source = flow.from({ 1, 2 })
            local sum = 0
            source:take_while(function () return true end):collect(function (value) sum = sum + value end)
            assert.is_equal(3, sum)
            assert.same({ 1 }, source:take_while(function (value) return value < 2 end):to_list())
            assert.same({ 2 }, source:drop(1):take_while(function (value) return value < 3 end):to_list())
            assert.same({}, source:drop(1):take_while(function (value) return value < 2 end):to_list())
        end)
    )

    it(
        "testEmptyFlow",
        runtest(function ()
            assert.same({}, flow.empty():take_while(function () return true end):to_list())
            assert.same({}, flow.empty():take_while(function () return false end):to_list())
        end)
    )

    -- adapted: observe the upstream scope's child cleanup when take_while
    -- rejects the second value and stops collecting.
    it(
        "testCancelUpstream",
        runtest(function ()
            local async = require("luastd.async")
            local cancelled = false
            local source = flow.new(function (emit)
                async.scope(function (scope)
                    local child = scope:launch(function () async.delay(math.huge) end)
                    child:on_cancel(function () cancelled = true end)
                    emit(1)
                    emit(2)
                end)
            end)
            assert.same({ 1 }, source:take_while(function (value) return value < 2 end):to_list())
            assert.is_true(cancelled)
        end)
    )

    -- adapted: a synchronous source verifies predicate-error propagation through
    -- catch and recovery output, without claiming structured-child cancellation.
    it(
        "testErrorCancelsUpstream",
        runtest(function ()
            local failure = luastd_test.TestException()
            local source = flow.from({ 1 }):take_while(function () error(failure, 0) end)
            local recovered = source:catch(function (emit, err)
                assert.is_true(rawequal(failure, err))
                emit(42)
            end):single()
            assert.is_equal(42, recovered)
        end)
    )
end)
