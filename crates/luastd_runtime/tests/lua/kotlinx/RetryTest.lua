local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/RetryTest.kt@1.11.0
describe("RetryTest", function ()
    -- adapted: retry_when takes an attempt index and collect replaces sum;
    -- the callback order and retry count match the Kotlin test.
    it(
        "testRetryWhen",
        runtest(function (t)
            t:expect(1)
            local counter = 0
            local source = flow.new(function (emit)
                emit(1)
                counter = counter + 1
                error(luastd_test.TestException())
            end):retry_when(function (cause, attempt)
                assert.is_equal("TestException", cause.kind)
                t:expect(2 + attempt)
                return attempt < 3
            end):catch(function (emit, cause)
                assert.is_equal("TestException", cause.kind)
                t:expect(6)
            end)
            local values = source:to_list()
            local sum = 0
            for _, value in ipairs(values) do
                sum = sum + value
            end
            assert.is_equal(4, sum)
            t:finish(7)
        end)
    )

    -- adapted: verify retry count and re-emission with collect; Flow has no sum
    -- terminal operator, and its synchronous retry API has no coroutine context.
    it(
        "testRetry",
        runtest(function ()
            local counter = 0
            local values = flow.new(function (emit)
                emit(1)
                counter = counter + 1
                if counter < 4 then error(luastd_test.TestException()) end
            end)

            local result = values:retry(4):to_list()
            local sum = 0
            for _, value in ipairs(result) do
                sum = sum + value
            end
            assert.is_equal(4, sum)
            counter = 0
            local ok = pcall(function () values:to_list() end)
            assert.is_false(ok)
            counter = 0
            ok = pcall(function () values:retry(2):to_list() end)
            assert.is_false(ok)
        end)
    )

    -- adapted: retry's predicate is synchronous and receives the upstream
    -- error; collect and a loop replace the absent sum terminal.
    it(
        "testRetryPredicate",
        runtest(function ()
            local counter = 0
            local values = flow.new(function (emit)
                emit(1)
                counter = counter + 1
                if counter == 1 then error(luastd_test.TestException()) end
            end)
            local retried = values:retry(1, function (cause)
                return cause.kind == "TestException"
            end):to_list()
            local sum = 0
            for _, value in ipairs(retried) do
                sum = sum + value
            end
            assert.is_equal(2, sum)

            counter = 0
            local ok = pcall(function ()
                values:retry(1, function (cause) return cause.kind ~= "TestException" end):to_list()
            end)
            assert.is_false(ok)
        end)
    )

    -- adapted: the retry boundary tracks downstream callback errors and
    -- rethrows them without rerunning the upstream flow.
    it(
        "testRetryExceptionFromDownstream",
        runtest(function ()
            local executed = 0
            local source = flow.of_one(1):retry(42):map(function ()
                executed = executed + 1
                error(luastd_test.TestException())
            end)
            local ok = pcall(function () source:to_list() end)
            assert.is_false(ok)
            assert.is_equal(1, executed)
        end)
    )

    -- not-applicable: the flow builder cannot suspend inside withTimeout/hang;
    -- retry operates synchronously and cannot exercise timeout recovery.
    pending("testWithTimeoutRetried")

    -- not-applicable: upstream cancellation from a suspended flow is not
    -- expressible with the synchronous retry operator and current Flow builder.
    pending("testCancellationFromUpstreamIsNotRetried")

    -- adapted: with synchronous collection, the upstream finally error
    -- replaces the downstream error and must not be retried.
    it(
        "testUpstreamExceptionConcurrentWithDownstream",
        runtest(function ()
            local failure = luastd_test.TestException()
            local values = flow.new(function (emit)
                local ok, err = pcall(function ()
                    emit(1)
                end)
                assert.is_false(ok)
                assert.is_not_nil(err)
                error(failure, 0)
            end):retry(3, function () error("retry predicate should not run") end):on_each(function ()
                error(luastd_test.TestException2())
            end)
            local ok, err = pcall(function () values:to_list() end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
        end)
    )

    -- not-applicable: cancellation is uncatchable in luastd (ADR 0005), so a
    -- downstream CancellationException cannot participate in Kotlin's error arbitration.
    pending("testUpstreamExceptionConcurrentWithDownstreamCancellation")

    -- not-applicable: the Kotlin case requires retry to arbitrate a catchable
    -- upstream cancellation against a downstream error; luastd cancellation
    -- bypasses callbacks and pcall (ADR 0005).
    pending("testUpstreamCancellationIsIgnoredWhenDownstreamFails")
end)
