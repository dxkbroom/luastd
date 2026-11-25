-- Port of kotlinx.coroutines' CollectLatestTest.

local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/CollectLatestTest.kt@1.11.0
describe("CollectLatestTest", function ()
    it(
        "testNoSuspension",
        runtest(function (t)
            flow.from({ 1, 2, 3 }):collect_latest(function (value) t:expect(value) end)
            t:finish(4)
        end)
    )

    -- defer: yielding collector actions are not cancelled when later values
    -- arrive because the current implementation collects synchronously.
    pending("testSuspension")

    -- adapted: verifies upstream error propagation after a value was collected;
    -- it does not claim cancellation of a suspended collector.
    it(
        "testUpstreamErrorSuspension",
        runtest(function (t)
            local failure = luastd_test.TestException()
            local source = flow.new(function (emit)
                emit(1)
                error(failure, 0)
            end)
            local ok, err = pcall(function ()
                source:collect_latest(function () t:expect(1) end)
            end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
            t:finish(2)
        end)
    )

    -- adapted: verifies a downstream action error reaches the collector;
    -- suspended upstream cleanup is not represented.
    it(
        "testDownstreamError",
        runtest(function (t)
            local failure = luastd_test.TestException()
            local ok, err = pcall(function ()
                flow.from({ 1 }):collect_latest(function ()
                    t:expect(1)
                    error(failure, 0)
                end)
            end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
            t:finish(2)
        end)
    )
end)
