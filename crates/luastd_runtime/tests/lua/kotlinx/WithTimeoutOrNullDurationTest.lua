-- kotlin: kotlinx-coroutines-core/common/test/WithTimeoutOrNullDurationTest.kt@1.11.0
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return err
end

describe("WithTimeoutOrNullDurationTest", function ()
    -- adapted: the current API has raising with_timeout, so exercise the
    -- successful no-timeout path with a long timeout budget.
    it(
        "testBasicNoSuspend",
        runtest(function (t)
            t:expect(1)
            local result = async.with_timeout(10000, function ()
                t:expect(2)
                return "OK"
            end)
            assert.is_equal("OK", result)
            t:finish(3)
        end)
    )

    -- adapted: use the raising with_timeout API with a long budget; this covers
    -- the successful suspended path, not timeout-to-null behavior.
    it(
        "testBasicSuspend",
        runtest(function (t)
            t:expect(1)
            local result = async.with_timeout(10000, function ()
                t:expect(2)
                async.yield()
                t:expect(3)
                return "OK"
            end)
            assert.is_equal("OK", result)
            t:finish(4)
        end)
    )

    -- adapted: use with_timeout with a long budget to preserve the dispatch
    -- ordering while omitting the unsupported null-on-timeout result.
    it(
        "testDispatch",
        runtest(function (t)
            t:expect(1)
            async.launch(function ()
                t:expect(4)
                async.yield()
                t:expect(7)
            end)
            t:expect(2)
            local result = async.with_timeout(1000, function ()
                t:expect(3)
                async.yield()
                t:expect(5)
                return "OK"
            end)
            assert.is_equal("OK", result)
            t:expect(6)
            async.yield()
            t:finish(8)
        end)
    )

    -- defer: async.with_timeout raises Timeout on expiry; there is no API that
    -- converts a timed-out yielding loop into a nil result.
    pending("testYieldBlockingWithTimeout")

    -- defer: the suspended channel receive can be timed out, but the current
    -- API raises Timeout instead of returning Kotlin's null result.
    pending("testSmallTimeout")

    -- adapted: use a structured TestException instead of AssertionError and an
    -- infinite timeout; this still checks that body failures pass through.
    it(
        "testThrowException",
        runtest(function ()
            local failure = luastd_test.TestException()
            local err = error_of(function ()
                async.with_timeout(math.huge, function () error(failure, 0) end)
            end)
            assert.is_true(rawequal(failure, err))
        end)
    )

    -- defer: without with_timeout_or_null, nested timeout ownership cannot be
    -- distinguished to suppress only the outer timeout.
    pending("testInnerTimeout")

    -- defer: without with_timeout_or_null, this cannot verify that an inner
    -- Timeout remains visible instead of being suppressed by the outer scope.
    pending("testNestedTimeout")

    -- defer: the API has no timeout-to-null operation for the nested timeout
    -- loop and cannot check the bounded retry count after each null result.
    pending("testOuterTimeout")

    -- adapted: use a table with failing metamethods and rawequal, matching the
    -- existing WithTimeoutTest adaptation for Kotlin BadClass.
    it(
        "testBadClass",
        runtest(function ()
            local function bad()
                error("BadClass")
            end
            local value = setmetatable({}, { __eq = bad, __hash = bad, __tostring = bad, __len = bad })
            local result = async.with_timeout(100, function () return value end)
            assert.is_true(rawequal(value, result))
        end)
    )

    -- defer: async.with_timeout raises Timeout rather than returning nil when
    -- the delay exceeds its deadline.
    pending("testNullOnTimeout")

    -- defer: cancellation cannot be caught to return a body result (ADR 0005),
    -- and no timeout-to-null builder exists.
    pending("testSuppressExceptionWithResult")

    -- defer: ADR 0005 makes cancellation uncatchable, and no timeout-to-null
    -- builder exists to distinguish the body failure from the timeout.
    pending("testSuppressExceptionWithAnotherException")

    -- defer: with_timeout reports an immediate Timeout error for non-positive
    -- durations; no API returns null for these timeout cases.
    pending("testNegativeTimeout")

    -- adapted: verify a body TestException escapes with_timeout; use the
    -- runtime's structured error instead of relying on Kotlin's test exception.
    it(
        "testExceptionFromWithinTimeout",
        runtest(function (t)
            t:expect(1)
            local failure = luastd_test.TestException()
            local err = error_of(function ()
                t:expect(2)
                async.with_timeout(1000, function ()
                    t:expect(3)
                    error(failure, 0)
                end)
                t:expect_unreached()
            end)
            assert.is_true(rawequal(failure, err))
            t:finish(4)
        end)
    )
end)
