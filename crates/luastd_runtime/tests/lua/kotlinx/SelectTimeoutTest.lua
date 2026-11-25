-- kotlin: kotlinx-coroutines-core/common/test/selects/SelectTimeoutTest.kt@1.11.0
describe("SelectTimeoutTest", function ()
    -- defer: async.with_timeout bounds one body; these cases require competing
    -- select/onTimeout clauses, and the unbiased case also requires
    -- select_unbiased. A single timeout cannot reproduce their assertions.
    pending("testBasic")
    pending("testZeroTimeout")
    pending("testNegativeTimeout")
    pending("testUnbiasedNegativeTimeout")
end)
