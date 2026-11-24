-- Port of kotlinx.coroutines' DelayTest (see AGENTS.md, "Kotlin test
-- ports"). A cancelled deferred is observed with `try_await`, which reports
-- `JobCancelled` as a value.
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

-- kotlin: kotlinx-coroutines-core/common/test/DelayTest.kt@1.11.0
describe("DelayTest", function ()
    it(
        "testCancellation",
        runtest(function (t)
            run_and_cancel(1000, t)
        end)
    )

    -- adapted: Lua numbers do not have Kotlin's signed Long range; infinity
    -- maps to the runtime's saturating never-completing duration.
    it(
        "testMaxLongValue",
        runtest(function (t)
            run_and_cancel(math.huge, t)
        end)
    )

    -- adapted: `Int.MAX_VALUE` is exactly representable as a Lua number.
    it(
        "testMaxIntValue",
        runtest(function (t)
            run_and_cancel(2147483647, t)
        end)
    )

    it(
        "testRegularDelay",
        runtest(function (t)
            local deferred = async.async(function ()
                t:expect(2)
                async.delay(1)
                t:expect(3)
            end)
            t:expect(1)
            async.yield()
            assert.is_true(async.try_await(deferred))
            t:finish(4)
        end)
    )
end)
