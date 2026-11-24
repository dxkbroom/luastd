-- Port of kotlinx.coroutines' RetryTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/RetryTest.kt@1.11.0
describe("RetryTest", function ()
    it("testRetry", function ()
        local attempts = 0
        local r = flow.new(function (emit)
            attempts = attempts + 1
            if attempts == 1 then error("boom") end
            emit(42)
        end):retry(1):to_list()
        assert.is_equal(1, #r)
        assert.is_equal(42, r[1])
    end)

    it("testRetryPredicate", function ()
        local attempts = 0
        local r = flow.new(function (emit)
            attempts = attempts + 1
            if attempts == 1 then error("boom") end
            emit(7)
        end):retry(2, function (e) return true end):to_list()
        assert.is_equal(1, #r)
        assert.is_equal(7, r[1])
    end)

    -- defer: cancellation/error/downstream semantics.
    pending("testCancellationFromUpstreamIsNotRetried")
    pending("testRetryExceptionFromDownstream")
    pending("testRetryWhen")
    pending("testUpstreamCancellationIsIgnoredWhenDownstreamFails")
    pending("testUpstreamExceptionConcurrentWithDownstream")
    pending("testUpstreamExceptionConcurrentWithDownstreamCancellation")
    pending("testWithTimeoutRetried")
end)