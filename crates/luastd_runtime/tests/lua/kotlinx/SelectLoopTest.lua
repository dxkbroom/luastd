-- kotlin: kotlinx-coroutines-core/common/test/selects/SelectLoopTest.kt@1.11.0
describe("SelectLoopTest", function ()
    -- defer: the current API has no select expression or channel/job clauses
    -- (`onReceiveCatching`, `onJoin`) to test cancellation of a select loop.
    pending("testChannelSelectLoop")
end)
