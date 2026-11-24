-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/SampleTest.kt@1.11.0
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

describe("SampleTest", function ()
    -- not-applicable: luastd has no Flow:sample operator or virtual-time
    -- scheduler for checking which pending value each interval emits.
    pending("testBasic")

    -- not-applicable: Flow:sample and virtual-time sampling intervals are absent.
    pending("testDelayedFirst")

    -- not-applicable: Flow:sample and virtual-time sampling intervals are absent.
    pending("testBasic2")

    -- not-applicable: this asserts sample's fixed-period tick behavior; no
    -- sample operator or virtual-time scheduler is exposed.
    pending("testFixedDelay")

    -- not-applicable: Flow:sample is absent, and Lua nil cannot be represented
    -- as an emitted value in a sequence or channel.
    pending("testSingleNull")

    -- not-applicable: Flow:sample is absent, and nil emissions are unsupported
    -- by the channel-backed flow pipeline.
    pending("testBasicWithNulls")

    -- not-applicable: even an empty flow's sample terminal behavior depends on
    -- the unavailable sample operator.
    pending("testEmpty")

    -- not-applicable: Flow:sample is absent; the scalar case tests its
    -- interval-longer-than-the-source behavior.
    pending("testScalar")

    -- not-applicable: this depends on virtual-time tick scheduling across long
    -- quiet periods, which luastd does not provide.
    pending("testLongWait")

    -- not-applicable: Flow:sample is absent; paced interval selection cannot
    -- be expressed by the current flow API.
    pending("testPace")

    -- not-applicable: there is no sample operator to coordinate the upstream
    -- failure with an active sampling collector.
    pending("testUpstreamError")

    -- not-applicable: besides the missing sample operator, Kotlin catches
    -- CancellationException to continue assertions; luastd cancellation is
    -- uncatchable (ADR 0005).
    pending("testUpstreamErrorCancellationException")

    -- not-applicable: Flow:sample is absent and luastd has no dispatcher
    -- contexts for this upstream-error isolation case.
    pending("testUpstreamErrorIsolatedContext")

    -- not-applicable: without sample, there is no sampling interval that can
    -- remain untriggered while an upstream error propagates.
    pending("testUpstreamErrorSampleNotTriggered")

    -- not-applicable: Flow:sample and dispatcher contexts are absent, so the
    -- isolated untriggered-sample error path cannot be represented.
    pending("testUpstreamErrorSampleNotTriggeredInIsolatedContext")

    -- not-applicable: there is no sample operator or interval collector to
    -- cancel when downstream mapping fails.
    pending("testDownstreamError")

    -- not-applicable: Flow:sample and dispatcher contexts are absent for this
    -- downstream-error context case.
    pending("testDownstreamErrorIsolatedContext")

    -- not-applicable: duration-based sample overloads and virtual time are not
    -- part of luastd's flow API.
    pending("testDurationBasic")

    -- adapted: Flow:debounce is lazy in luastd, so validation occurs when
    -- collected; Kotlin validates when constructing the operator.
    it(
        "testFailsWithIllegalArgument",
        runtest(function ()
            local ok, err = pcall(function () flow.empty():debounce(-1):to_list() end)
            assert.is_false(ok)
            assert.is_equal("InvalidArgument", err.kind)
        end)
    )
end)
