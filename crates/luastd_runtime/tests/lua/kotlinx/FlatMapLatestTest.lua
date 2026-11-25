-- Port of kotlinx.coroutines' FlatMapLatestTest.
-- The current operator flattens inner flows sequentially; switching semantics remain unsupported.
-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/FlatMapLatestTest.kt@1.11.0
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("FlatMapLatestTest", function ()
    -- adapted: this checks value flattening only; it does not exercise cancellation or switching.
    it(
        "testFlatMapLatest",
        runtest(function ()
            local result = flow.from({ 1, 2, 3 }):flat_map_latest(function (value)
                return flow.from({ value, value + 1 })
            end):to_list()
            assert.same({ 1, 2, 2, 3, 3, 4 }, result)
        end)
    )

    -- adapted: this checks sequential value emission only, not latest-inner cancellation.
    it(
        "testEmission",
        runtest(function ()
            local result = flow.from({ 0, 1, 2, 3, 4 }):flat_map_latest(function (value)
                return flow.of_one(value)
            end):to_list()
            assert.same({ 0, 1, 2, 3, 4 }, result)
        end)
    )

    -- defer: requires cancelling an active inner flow when the next upstream value arrives.
    pending("testSwitchIntuitiveBehaviour")

    -- defer: relies on latest-inner cancellation with rendezvous backpressure and scheduler ordering.
    pending("testSwitchRendevouzBuffer")

    -- defer: requires hanging inner flows to be cancelled when a later value supersedes them.
    pending("testHangFlows")

    -- adapted: an empty result table represents Kotlin's null from singleOrNull.
    it(
        "testEmptyFlow",
        runtest(function ()
            local result = flow.empty():flat_map_latest(function () return flow.of_one(1) end):to_list()
            assert.same({}, result)
        end)
    )

    -- adapted: checks inner failure propagation and the emitted prefix; it does
    -- not claim that a prior suspended inner is cancelled before the failure.
    it(
        "testFailureInTransform",
        runtest(function (t)
            local failure = luastd_test.TestException()
            local values = {}
            local source = flow.from({ 1, 2 }):flat_map_latest(function (value)
                if value == 1 then return flow.of_one(value) end
                return flow.new(function ()
                    t:expect(2)
                    error(failure, 0)
                end)
            end)
            local ok, err = pcall(function ()
                source:collect(function (value)
                    t:expect(1)
                    values[#values + 1] = value
                end)
            end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
            assert.same({ 1 }, values)
            t:finish(3)
        end)
    )

    -- adapted: checks downstream failure propagation through a synchronous
    -- inner flow; there is no suspended inner to clean up.
    it(
        "testFailureDownstream",
        runtest(function (t)
            local failure = luastd_test.TestException()
            local ok, err = pcall(function ()
                flow.from({ 1 }):flat_map_latest(function (value) return flow.of_one(value) end):collect(function ()
                    t:expect(1)
                    error(failure, 0)
                end)
            end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
            t:finish(2)
        end)
    )

    -- adapted: checks upstream error propagation after a value passes through a
    -- completed inner; the original suspended-inner cancellation is omitted.
    it(
        "testFailureUpstream",
        runtest(function (t)
            local failure = luastd_test.TestException()
            local source = flow.new(function (emit)
                t:expect(1)
                emit(1)
                t:expect(4)
                error(failure, 0)
            end):flat_map_latest(function (value)
                t:expect(2)
                return flow.of_one(value)
            end)
            local ok, err = pcall(function ()
                source:collect(function (value)
                    assert.is_equal(1, value)
                    t:expect(3)
                end)
            end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
            t:finish(5)
        end)
    )

    -- adapted: value flattening and take(1) are supported; no inner switching is exercised.
    it(
        "testTake",
        runtest(function ()
            local result = flow.from({ 1, 2, 3, 4, 5 }):flat_map_latest(function (value)
                return flow.of_one(value)
            end):take(1):to_list()
            assert.same({ 1 }, result)
        end)
    )
end)
