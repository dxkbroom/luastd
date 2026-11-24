-- kotlin: kotlinx-coroutines-core/common/test/CancelledParentAttachTest.kt@1.11.0
local async = require("luastd.async")
local runtest = require("luastd_test").runtest

describe("CancelledParentAttachTest", function ()
    -- not-applicable: async has no CoroutineContext/parent overload, so it
    -- cannot attach to an independently cancelled Job without cancelling the
    -- current test scope as well.
    pending("testAsync")

    -- adapted: luastd has no invokeOnCompletion callback; assert that a child
    -- attached to a cancelled parent is immediately cancelled and never runs.
    it(
        "testLaunch",
        runtest(function (t)
            local parent = async.supervisor_job()
            parent:cancel()
            t:expect(1)
            local child = async.launch(async.context(parent), function ()
                t:expect_unreached()
            end)
            assert.is_true(child:is_cancelled())
            async.yield()
            t:expect(2)
            t:finish(3)
        end)
    )

    -- not-applicable: async.produce always attaches to the current coroutine;
    -- it has no context/parent parameter for this isolated attachment case.
    pending("testProduce")

    -- not-applicable: luastd does not expose the deprecated BroadcastChannel
    -- builder or configurable CoroutineStart modes.
    pending("testBroadcast")

    -- not-applicable: Kotlin catches cancellation to continue checking several
    -- scope builders; luastd cancellation is uncatchable (ADR 0005), and the
    -- Kotlin flowScope builder is also absent.
    pending("testScopes")
end)
