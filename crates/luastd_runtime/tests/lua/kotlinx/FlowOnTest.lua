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
    pending("testAtomicStart")
    pending("testCancellation")
    pending("testCancelledFlowOn")
    pending("testException")
    pending("testFlowOnAndOperators")
    pending("testFlowOnCancellation")
    pending("testFlowOnCancellationHappensBefore")
    pending("testFlowOnDownstreamOperator")
    pending("testFlowOnThrowingConsumer")
    pending("testFlowOnThrowingOperator")
    pending("testFlowOnThrowingSource")
    pending("testFlowOnWithJob")
    pending("testIllegalArgumentException")
    pending("testIndependentOperatorContext")
    pending("testMultipleFlowOn")
    pending("testTimeoutExceptionDownstream")
    pending("testTimeoutExceptionUpstream")
end)