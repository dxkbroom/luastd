-- Port of kotlinx.coroutines' CatchTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/CatchTest.kt@1.11.0
describe("CatchTest", function ()
    it("testCatchEmit", function ()
        local r = flow.from({ 1, 2 }):map(function (x)
            if x == 2 then error("boom") end
            return x
        end):catch(function (emit, err)
            emit(0)
        end):to_list()
        assert.is_equal(2, #r)
        assert.is_equal(1, r[1])
        assert.is_equal(0, r[2])
    end)

    it("testCatchEmitAll", function ()
        local r = flow.new(function (emit)
            emit(1)
            error("boom")
        end):catch(function (emit, err)
            emit(2)
            emit(3)
        end):to_list()
        assert.is_equal(3, #r)
        assert.is_equal(1, r[1])
        assert.is_equal(2, r[2])
        assert.is_equal(3, r[3])
    end)

    -- defer: cancellation/error semantics.
    pending("testCancellationFromUpstreamCatch")
    pending("testCatchContext")
    pending("testCatchEmitAllExceptionFromDownstream")
    pending("testCatchEmitExceptionFromDownstream")
    pending("testUpstreamCancellationIsIgnoredWhenDownstreamFails")
    pending("testUpstreamExceptionConcurrentWithDownstream")
    pending("testUpstreamExceptionConcurrentWithDownstreamCancellation")
    pending("testWithTimeoutCatch")
end)
