-- kotlin: kotlinx-coroutines-core/common/test/NonCancellableTest.kt@1.11.0
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("NonCancellableTest", function ()
    -- not-applicable: there is no NonCancellable context element; cancellation
    -- cannot be suppressed for ordinary coroutine work (ADR 0005).
    pending("testNonCancellable")

    -- not-applicable: luastd cancellation has no user-supplied cause, and
    -- NonCancellable contexts are not exposed (ADR 0005).
    pending("testNonCancellableWithException")

    -- adapted: async.finally runs cleanup outside cancellation, including
    -- across yields; it provides the supported cleanup guarantee without a
    -- general NonCancellable context.
    it(
        "testNonCancellableFinally",
        runtest(function (t)
            t:expect(1)
            local job = async.launch(function ()
                t:expect(2)
                async.finally(function () async.await_cancellation() end, function ()
                    t:expect(4)
                    async.yield()
                    t:expect(5)
                end)
                t:expect_unreached()
            end)
            async.yield()
            job:cancel()
            t:expect(3)
            assert.is_true(job:is_cancelled())
            async.join(job)
            t:finish(6)
        end)
    )

    -- not-applicable: repeating a NonCancellable context requires that absent
    -- context element; async.finally only provides a cleanup region.
    pending("testNonCancellableTwice")
end)
