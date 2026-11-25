-- kotlin: kotlinx-coroutines-core/common/test/selects/SelectTimeoutDurationTest.kt@1.11.0
describe("SelectTimeoutDurationTest", function ()
    -- defer: async.with_timeout can bound one body, but the current API has no
    -- select/onTimeout clauses, so competing and zero/negative timeout clauses
    -- cannot be represented; select_unbiased is also absent.
    pending("testBasic")
    pending("testZeroTimeout")
    pending("testNegativeTimeout")
    pending("testUnbiasedNegativeTimeout")
end)
