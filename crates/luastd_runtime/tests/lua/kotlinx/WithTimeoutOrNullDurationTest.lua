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
    -- adapted: duration literals are millisecond numbers in the Lua API.
    it(
        "testBasicNoSuspend",
        runtest(function (t)
            t:expect(1)
            local result = async.with_timeout_or_null(10000, function ()
                t:expect(2)
                return "OK"
            end)
            assert.is_equal("OK", result)
            t:finish(3)
        end)
    )

    -- adapted: duration literals are millisecond numbers in the Lua API.
    it(
        "testBasicSuspend",
        runtest(function (t)
            t:expect(1)
            local result = async.with_timeout_or_null(10000, function ()
                t:expect(2)
                async.yield()
                t:expect(3)
                return "OK"
            end)
            assert.is_equal("OK", result)
            t:finish(4)
        end)
    )

    -- adapted: duration literals are millisecond numbers in the Lua API.
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
            local result = async.with_timeout_or_null(1000, function ()
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

    it(
        "testYieldBlockingWithTimeout",
        runtest(function (t)
            t:expect(1)
            local result = async.with_timeout_or_null(100, function ()
                while true do
                    async.yield()
                end
            end)
            assert.is_nil(result)
            t:finish(2)
        end)
    )

    it(
        "testSmallTimeout",
        runtest(function ()
            local channel = async.channel(1)
            assert.is_nil(async.with_timeout_or_null(1, function () return channel:receive() end))
        end)
    )

    -- adapted: use a structured TestException instead of AssertionError and an
    -- infinite timeout; this still checks that body failures pass through.
    it(
        "testThrowException",
        runtest(function ()
            local failure = luastd_test.TestException()
            local err = error_of(function ()
                async.with_timeout_or_null(math.huge, function () error(failure, 0) end)
            end)
            assert.is_true(rawequal(failure, err))
        end)
    )

    it(
        "testInnerTimeout",
        runtest({ expected = "Timeout" }, function (t)
            async.with_timeout_or_null(1000, function ()
                async.with_timeout(10, function ()
                    while true do
                        async.yield()
                    end
                end)
                t:expect_unreached()
            end)
            t:expect_unreached()
        end)
    )

    it(
        "testNestedTimeout",
        runtest({ expected = "Timeout" }, function (t)
            async.with_timeout_or_null(math.huge, function ()
                async.with_timeout(10, function ()
                    async.delay(math.huge)
                    return 1
                end)
            end)
            t:expect_unreached()
        end)
    )

    it(
        "testOuterTimeout",
        runtest(function ()
            local counter = 0
            local result = async.with_timeout_or_null(320, function ()
                while true do
                    local inner = async.with_timeout_or_null(150, function ()
                        while true do
                            async.yield()
                        end
                    end)
                    assert.is_nil(inner)
                    counter = counter + 1
                end
            end)
            assert.is_nil(result)
            assert.is_true(counter >= 1 and counter <= 2)
        end)
    )

    -- adapted: use a table with failing metamethods and rawequal, matching the
    -- existing WithTimeoutTest adaptation for Kotlin BadClass.
    it(
        "testBadClass",
        runtest(function ()
            local function bad()
                error("BadClass")
            end
            local value = setmetatable({}, { __eq = bad, __hash = bad, __tostring = bad, __len = bad })
            local result = async.with_timeout_or_null(100, function () return value end)
            assert.is_true(rawequal(value, result))
        end)
    )

    it(
        "testNullOnTimeout",
        runtest(function (t)
            t:expect(1)
            local result = async.with_timeout_or_null(100, function ()
                t:expect(2)
                async.delay(1000)
                t:expect_unreached()
                return "OK"
            end)
            assert.is_nil(result)
            t:finish(3)
        end)
    )

    -- not-applicable: ADR 0005 makes timeout cancellation uncatchable, so the
    -- Kotlin cancellation catch cannot continue and return a body result.
    pending("testSuppressExceptionWithResult")

    -- not-applicable: ADR 0005 makes timeout cancellation uncatchable, so the
    -- Kotlin catch cannot replace the timeout with TestException.
    pending("testSuppressExceptionWithAnotherException")

    it(
        "testNegativeTimeout",
        runtest(function (t)
            t:expect(1)
            local ran = false
            assert.is_nil(async.with_timeout_or_null(-1, function () ran = true end))
            assert.is_nil(async.with_timeout_or_null(0, function () ran = true end))
            assert.is_false(ran)
            t:finish(2)
        end)
    )

    -- adapted: use the runtime's structured TestException instead of Kotlin's.
    it(
        "testExceptionFromWithinTimeout",
        runtest(function (t)
            t:expect(1)
            local failure = luastd_test.TestException()
            local err = error_of(function ()
                t:expect(2)
                async.with_timeout_or_null(1000, function ()
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
