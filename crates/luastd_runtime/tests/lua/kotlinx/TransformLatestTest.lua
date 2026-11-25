-- Port of kotlinx.coroutines' TransformLatestTest.

local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/TransformLatestTest.kt@1.11.0
describe("TransformLatestTest", function ()
    -- adapted: the transform does not suspend, so this checks emitted values
    -- and order without claiming Kotlin's cancellation/switching behavior.
    it(
        "testTransformLatest",
        runtest(function ()
            local result = flow.from({ 1, 2, 3 }):transform_latest(function (emit, value)
                emit(value)
                emit(value + 1)
            end):to_list()
            assert.same({ 1, 2, 2, 3, 3, 4 }, result)
        end)
    )

    -- adapted: the transforms are synchronous; this checks the sequential
    -- emission contract, not cancellation of a previous transform.
    it(
        "testEmission",
        runtest(function ()
            local result = flow.from({ 0, 1, 2, 3, 4 }):transform_latest(function (emit, value)
                emit(value)
            end):to_list()
            assert.same({ 0, 1, 2, 3, 4 }, result)
        end)
    )

    -- defer: expects a new upstream value to cancel a suspended transform child.
    pending("testSwitchIntuitiveBehaviour")

    -- defer: relies on scheduler interleaving, rendezvous buffering, and
    -- cancellation of prior transform children.
    pending("testSwitchRendezvousBuffer")
    pending("testSwitchBuffer")

    -- defer: the current operator cannot cancel a transform suspended in hang.
    pending("testHangFlows")

    -- adapted: no single_or_null terminal exists; an empty result list verifies
    -- that the transform emits nothing for an empty source.
    it(
        "testEmptyFlow",
        runtest(function ()
            local result = flow.empty():transform_latest(function (emit) emit(1) end):to_list()
            assert.same({}, result)
        end)
    )

    -- defer: per-transform coroutine contexts are not represented by this operator.
    pending("testIsolatedContext")

    -- defer: these cases depend on failures and cancellation across concurrent
    -- transform/upstream/downstream coroutines.
    pending("testFailureInTransform")
    pending("testFailureDownstream")
    pending("testFailureUpstream")

    -- adapted: a synchronous transform supports take's early-stop sentinel;
    -- this does not test switching between transform children.
    it(
        "testTake",
        runtest(function ()
            local result = flow.from({ 1, 2, 3, 4, 5 }):transform_latest(function (emit, value)
                emit(value)
            end):take(1):to_list()
            assert.same({ 1 }, result)
        end)
    )
end)
