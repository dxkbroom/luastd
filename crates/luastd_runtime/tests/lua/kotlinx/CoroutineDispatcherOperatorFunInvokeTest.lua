-- kotlin: kotlinx-coroutines-core/common/test/CoroutineDispatcherOperatorFunInvokeTest.kt@1.11.0
local async = require("luastd.async")
local runtest = require("luastd_test").runtest

describe("CoroutineDispatcherOperatorFunInvokeTest", function ()
    -- not-applicable: this specifically invokes a wrapped CoroutineDispatcher;
    -- luastd exposes CoroutineContext scopes but no dispatcher object/operator.
    pending("testThrowException")

    -- adapted: with_context provides the closest supported same-context scope;
    -- verify its child completes before the block returns and keeps the value.
    it(
        "testWithContextChildWaitSameContext",
        runtest(function (t)
            t:expect(1)
            local value = async.with_context(async.context(), function ()
                t:expect(2)
                async.launch(function () t:expect(4) end)
                t:expect(3)
                return "OK"
            end)
            assert.is_equal("OK", value)
            t:finish(5)
        end)
    )
end)
