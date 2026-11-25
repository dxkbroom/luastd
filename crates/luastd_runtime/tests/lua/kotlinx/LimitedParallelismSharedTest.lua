-- kotlin: kotlinx-coroutines-core/common/test/LimitedParallelismSharedTest.kt@1.11.0
describe("LimitedParallelismSharedTest", function ()
    -- not-applicable: luastd runs coroutines on one current-thread executor and
    -- exposes no Dispatchers.Default or limitedParallelism views to schedule
    -- the two independently limited jobs in this test.
    pending("testLimitedDefault")

    -- not-applicable: there is no dispatcher API or limitedParallelism
    -- constructor whose argument validation and Int.MAX_VALUE behavior can be
    -- exercised.
    pending("testParallelismSpec")

    -- not-applicable: luastd does not expose CoroutineDispatcher dispatch,
    -- Runnable worker queues, or limited-parallelism scheduling wrappers.
    pending("testLimitedParallelismOfOccasionallyFailingDispatcher")
end)
