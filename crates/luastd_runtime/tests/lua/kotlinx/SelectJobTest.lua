-- kotlin: kotlinx-coroutines-core/common/test/selects/SelectJobTest.kt@1.11.0
describe("SelectJobTest", function ()
    -- defer: Job cancellation and join are available, but luastd has no select
    -- builder or Job:on_join clause to select a completed job non-suspendingly.
    pending("testSelectCompleted")

    -- defer: async.join suspends but cannot be raced inside a select clause
    -- against job cancellation and report selection dispatch order.
    pending("testSelectIncomplete")

    -- defer: launch_lazy is supported, but there is no select on_join clause
    -- to test whether selecting a lazy job starts it and returns its result.
    pending("testSelectLazy")
end)
