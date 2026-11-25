local async = require("luastd.async")
local runtest = require("luastd_test").runtest

local function run_and_cancel(ms, t)
    t:expect(1)
    local deferred = async.async(function ()
        t:expect(2)
        async.delay(ms)
        t:expect_unreached()
    end)
    async.yield()
    t:expect(3)
    assert.is_true(deferred:is_active())
    deferred:cancel()
    local ok, err = async.try_await(deferred)
    assert.is_false(ok)
    assert.is_equal("JobCancelled", err.kind)
    t:finish(4)
end

-- kotlin: kotlinx-coroutines-core/common/test/DelayDurationTest.kt@1.11.0
describe("DelayDurationTest", function ()
    -- adapted: Kotlin Duration is not exposed; async.delay takes numeric
    -- milliseconds, so one second is represented by 1000 milliseconds.
    it(
        "testCancellation",
        runtest(function (t)
            run_and_cancel(1000, t)
        end)
    )

    -- adapted: positive infinity is the runtime's never-completing delay.
    it(
        "testInfinite",
        runtest(function (t)
            run_and_cancel(math.huge, t)
        end)
    )

    -- adapted: the Lua API accepts milliseconds and this uses 1 ms to keep
    -- the real-time runtime test short while preserving the scheduling case.
    it(
        "testRegularDelay",
        runtest(function (t)
            local deferred = async.async(function ()
                t:expect(2)
                async.delay(1)
                t:expect(4)
            end)
            t:expect(1)
            async.yield()
            t:expect(3)
            assert.is_true(async.try_await(deferred))
            t:finish(5)
        end)
    )

    -- adapted: Kotlin rounds 1 ns up to a 1 ms delay; Lua's API has no
    -- Duration conversion, so exercise that resulting 1 ms delay directly.
    it(
        "testNanoDelay",
        runtest(function (t)
            local deferred = async.async(function ()
                t:expect(2)
                async.delay(1)
                t:expect(4)
            end)
            t:expect(1)
            async.yield()
            t:expect(3)
            assert.is_true(async.try_await(deferred))
            t:finish(5)
        end)
    )
end)
