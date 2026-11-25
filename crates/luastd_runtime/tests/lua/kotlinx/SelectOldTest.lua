-- kotlin: kotlinx-coroutines-core/common/test/selects/SelectOldTest.kt@1.11.0
describe("SelectOldTest", function ()
    -- defer: this registers Job:onJoin in the legacy selectOld builder; luastd
    -- has no select builder or on_join clause-registration API.
    pending("testSelectCompleted")

    -- defer: the unbiased legacy select builder and Job:onJoin clause are
    -- absent, so selection order among ready clauses cannot be exercised.
    pending("testSelectUnbiasedCompleted")

    -- defer: this suspends while waiting for Job:onJoin to become selectable;
    -- luastd exposes Job:join but no selectOld/on_join operation.
    pending("testSelectIncomplete")

    -- defer: luastd has no selectUnbiasedOld builder or Job:onJoin clause to
    -- wait for the incomplete job's cancellation.
    pending("testSelectUnbiasedIncomplete")

    -- defer: completed-job selection and unbiased clause dispatch require the
    -- absent selectUnbiasedOld and Job:onJoin APIs.
    pending("testSelectUnbiasedComplete")

    -- defer: this invokes and catches an exception from a select builder; luastd
    -- exposes no select builder in which the exception can occur.
    pending("testSelectUnbiasedThrows")

    -- defer: registering onJoin is what should start and await this lazy job;
    -- luastd has no selectOld/on_join clause integration.
    pending("testSelectLazy")

    -- defer: neither selectUnbiasedOld nor Job:onJoin exists to trigger and
    -- await the lazy job through an unbiased selected clause.
    pending("testSelectUnbiasedLazy")
end)
