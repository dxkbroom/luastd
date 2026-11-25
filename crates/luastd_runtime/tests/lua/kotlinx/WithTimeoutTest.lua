-- Port of kotlinx.coroutines' WithTimeoutTest (see AGENTS.md, "Kotlin test
-- ports"). Kotlin's `TimeoutCancellationException` is the `Timeout` kind of
-- luastd.Error here: catchable, and not a cancellation (ADR 0005).
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

--- Kotlin's `try { ... } catch (e: ...)`: the error `fn` raised.
---@param fn fun()
---@return any
local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return err
end

-- kotlin: kotlinx-coroutines-core/common/test/WithTimeoutTest.kt@1.11.0
describe("WithTimeoutTest", function ()
    -- Tests a case of no timeout and no suspension inside.
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

    -- Tests a case of no timeout and one suspension inside.
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

    -- Tests proper dispatching of `with_timeout` blocks.
    it(
        "testDispatch",
        runtest(function (t)
            t:expect(1)
            async.launch(function ()
                t:expect(4)
                async.yield() -- back to main
                t:expect(7)
            end)
            t:expect(2)
            -- test that it does not yield to the above job when started
            local result = async.with_timeout(1000, function ()
                t:expect(3)
                async.yield() -- yield only now
                t:expect(5)
                return "OK"
            end)
            assert.is_equal("OK", result)
            t:expect(6)
            async.yield() -- back to launch
            t:finish(8)
        end)
    )

    -- Tests that a 100% CPU-consuming loop will react on timeout if it has yields.
    it(
        "testYieldBlockingWithTimeout",
        runtest({ expected = "Timeout" }, function ()
            async.with_timeout(100, function ()
                while true do
                    async.yield()
                end
            end)
        end)
    )

    -- Tests that `with_timeout` waits for children coroutines to complete.
    it(
        "testWithTimeoutChildWait",
        runtest(function (t)
            t:expect(1)
            async.with_timeout(100, function ()
                t:expect(2)
                -- launch child with timeout
                async.launch(function ()
                    t:expect(4)
                end)
                t:expect(3)
                -- now will wait for child before returning
            end)
            t:finish(5)
        end)
    )

    -- adapted: Kotlin's BadClass throws from equals/hashCode/toString; here a
    -- table whose metamethods raise, compared with rawequal.
    it(
        "testBadClass",
        runtest(function ()
            local function bad()
                error("BadClass")
            end
            local value = setmetatable({}, { __eq = bad, __tostring = bad, __index = bad, __len = bad })
            local result = async.with_timeout(100, function ()
                return value
            end)
            assert.is_true(rawequal(value, result))
        end)
    )

    it(
        "testExceptionOnTimeout",
        runtest(function (t)
            t:expect(1)
            local err = error_of(function ()
                async.with_timeout(100, function ()
                    t:expect(2)
                    async.delay(1000)
                    t:expect_unreached()
                    return "OK"
                end)
            end)
            assert.is_equal("Timeout", err.kind)
            assert.is_equal("Timed out waiting for 100 ms", err.message)
            t:finish(3)
        end)
    )

    -- adapted: the body cannot catch its cancellation (ADR 0005), so the
    -- `catch` block becomes `async.finally` cleanup; the body's "OK" is lost
    -- either way and `with_timeout` still raises Timeout.
    it(
        "testSuppressExceptionWithResult",
        runtest({ expected = "Timeout" }, function (t)
            t:expect(1)
            async.with_timeout(100, function ()
                t:expect(2)
                async.finally(function () async.delay(1000) end, function () t:finish(3) end)
                return "OK"
            end)
            t:expect_unreached()
        end)
    )

    -- not-applicable: the body cannot catch its cancellation and raise another error
    -- instead (ADR 0005); `async.finally` keeps the body's error over the
    -- cleanup's, so the TestException never replaces the timeout.
    pending("testSuppressExceptionWithAnotherException")

    it(
        "testNegativeTimeout",
        runtest(function (t)
            t:expect(1)
            local err = error_of(function ()
                async.with_timeout(-1, function ()
                    t:expect_unreached()
                    return "OK"
                end)
            end)
            assert.is_equal("Timeout", err.kind)
            assert.is_equal("Timed out immediately", err.message)
            t:finish(2)
        end)
    )

    it(
        "testExceptionFromWithinTimeout",
        runtest(function (t)
            t:expect(1)
            local err = error_of(function ()
                t:expect(2)
                async.with_timeout(1000, function ()
                    t:expect(3)
                    error(luastd_test.TestException())
                end)
                t:expect_unreached()
            end)
            assert.is_equal("TestException", err.kind)
            t:finish(4)
        end)
    )

    -- adapted: luastd has no `invokeOnCompletion` handle to dispose and a scope
    -- has no `join`; checks the state of the returned timeout scope instead.
    it(
        "testIncompleteWithTimeoutState",
        runtest(function ()
            local timeout_job
            async.with_timeout(math.huge, function (scope)
                timeout_job = scope:coroutine_context():job()
            end)
            async.join(timeout_job)
            assert.is_true(timeout_job:is_completed())
            assert.is_false(timeout_job:is_active())
            assert.is_false(timeout_job:is_cancelled())
        end)
    )

    it(
        "testTimeoutCancellationExceptionIncludesCoroutineName",
        runtest(function ()
            local err = error_of(function ()
                async.with_context(async.context(async.coroutine_name("waiting for x")), function ()
                    async.with_timeout(1, function () async.delay(math.huge) end)
                end)
            end)
            assert.is_true(err.message:find("waiting for x", 1, true) ~= nil)
            assert.is_true(err.message:lower():find("timed out waiting", 1, true) ~= nil)
        end)
    )
end)
