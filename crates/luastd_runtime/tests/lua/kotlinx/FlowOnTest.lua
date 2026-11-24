-- Port of kotlinx.coroutines' FlowOnTest.
-- flow_on is implemented (context switching); dispatcher cases are not-applicable.
-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/FlowOnTest.kt@1.11.0
---@diagnostic disable: await-in-sync
local flow = require("luastd.flow")
local async = require("luastd.async")

describe("FlowOnTest", function ()
    it("testFlowOn", function ()
        local ctx = async.context(async.coroutine_name("worker"))
        local r = flow.from({ 1, 2, 3 }):flow_on(ctx):to_list()
        assert.is_equal(3, #r)
        assert.is_equal(1, r[1])
    end)

    -- not-applicable: dispatcher/context-optimization cases (no dispatchers).
    pending("testFlowOnAndOperators")
    pending("testFlowOnThrowingSource")
    pending("testFlowOnThrowingOperator")
    pending("testFlowOnDownstreamOperator")
    pending("testFlowOnThrowingConsumer")
    pending("testFlowOnWithJob")
    pending("testFlowOnCancellation")
    pending("testFlowOnCancellationHappensBefore")
    pending("testIndependentOperatorContext")
    pending("testMultipleFlowOn")
    pending("testTimeoutExceptionUpstream")
    pending("testTimeoutExceptionDownstream")
    pending("testCancellation")
    pending("testAtomicStart")
    pending("testException")
    pending("testIllegalArgumentException")
    pending("testCancelledFlowOn")
end)
