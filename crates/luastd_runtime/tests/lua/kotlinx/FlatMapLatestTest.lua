-- Port of kotlinx.coroutines' FlatMapLatestTest.
-- The current operator flattens inner flows sequentially; switching semantics remain unsupported.
-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/FlatMapLatestTest.kt@1.11.0
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

describe("FlatMapLatestTest", function ()
    -- adapted: this checks value flattening only; it does not exercise cancellation or switching.
    it("testFlatMapLatest", runtest(function ()
        local result = flow.from({ 1, 2, 3 }):flat_map_latest(function (value)
            return flow.from({ value, value + 1 })
        end):to_list()
        assert.same({ 1, 2, 2, 3, 3, 4 }, result)
    end))

    -- adapted: this checks sequential value emission only, not latest-inner cancellation.
    it("testEmission", runtest(function ()
        local result = flow.from({ 0, 1, 2, 3, 4 }):flat_map_latest(function (value)
            return flow.of_one(value)
        end):to_list()
        assert.same({ 0, 1, 2, 3, 4 }, result)
    end))

    -- defer: requires cancelling an active inner flow when the next upstream value arrives.
    pending("testSwitchIntuitiveBehaviour")

    -- defer: relies on latest-inner cancellation with rendezvous backpressure and scheduler ordering.
    pending("testSwitchRendevouzBuffer")

    -- defer: requires hanging inner flows to be cancelled when a later value supersedes them.
    pending("testHangFlows")

    -- adapted: an empty result table represents Kotlin's null from singleOrNull.
    it("testEmptyFlow", runtest(function ()
        local result = flow.empty():flat_map_latest(function () return flow.of_one(1) end):to_list()
        assert.same({}, result)
    end))

    -- defer: failure ordering depends on cancelling the previous inner flow before starting the next.
    pending("testFailureInTransform")

    -- defer: downstream failure requires propagation through cancellation of the active inner flow.
    pending("testFailureDownstream")

    -- defer: upstream failure ordering is asserted while the active inner flow is suspended.
    pending("testFailureUpstream")

    -- adapted: value flattening and take(1) are supported; no inner switching is exercised.
    it("testTake", runtest(function ()
        local result = flow.from({ 1, 2, 3, 4, 5 }):flat_map_latest(function (value)
            return flow.of_one(value)
        end):take(1):to_list()
        assert.same({ 1 }, result)
    end))
end)
