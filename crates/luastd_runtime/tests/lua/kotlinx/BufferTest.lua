-- Port of kotlinx.coroutines' BufferTest.

local flow = require("luastd.flow")
local async = require("luastd.async")
local runtest = require("luastd_test").runtest

local n = 200

local function check_buffer(capacity, transform)
    return runtest(function ()
        local produced = 0
        local source = flow.new(function (emit)
            for i = 0, n - 1 do
                produced = produced + 1
                emit(i)
            end
        end)
        local received = 0
        transform(source):collect(function (i)
            assert.is_equal(received, i)
            received = received + 1
            local lead = produced - received
            local bound = capacity == -1 and 0 or math.max(capacity, 1) + 1
            assert.is_true(lead <= bound)
        end)
        assert.is_equal(n, received)
    end)
end

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/BufferTest.kt@1.11.0
describe("BufferTest", function ()
    it("testBaseline", check_buffer(-1, function (source) return source end))
    -- adapted: Tokio does not guarantee Kotlin's dispatcher batch order;
    -- check the bounded producer lead and full ordered delivery instead.
    it("testBufferDefault", check_buffer(64, function (source) return source:buffer() end))
    -- adapted: check bounded producer lead and ordered delivery, not dispatch order.
    it("testBufferRendezvous", check_buffer(0, function (source) return source:buffer(0) end))

    -- adapted: check bounded producer lead and ordered delivery, not dispatch order.
    it("testBuffer1", check_buffer(1, function (source) return source:buffer(1) end))
    -- adapted: check bounded producer lead and ordered delivery, not dispatch order.
    it("testBuffer2", check_buffer(2, function (source) return source:buffer(2) end))

    -- adapted: check bounded producer lead and ordered delivery, not dispatch order.
    it("testBuffer3", check_buffer(3, function (source) return source:buffer(3) end))
    -- adapted: checks the fused effective capacity and ordered delivery;
    -- runtime task scheduling does not match Kotlin's batch trace.
    it("testBuffer00Fused", check_buffer(0, function (source) return source:buffer(0):buffer(0) end))
    -- adapted: checks the fused effective capacity and ordered delivery.
    it("testBuffer01Fused", check_buffer(1, function (source) return source:buffer(0):buffer(1) end))
    -- adapted: checks the fused effective capacity and ordered delivery.
    it("testBuffer11Fused", check_buffer(2, function (source) return source:buffer(1):buffer(1) end))
    -- adapted: checks the fused effective capacity and ordered delivery.
    it("testBuffer111Fused", check_buffer(3, function (source) return source:buffer(1):buffer(1):buffer(1) end))
    -- adapted: checks the fused effective capacity and ordered delivery.
    it("testBuffer123Fused", check_buffer(6, function (source) return source:buffer(1):buffer(2):buffer(3) end))
    -- adapted: repeated default capacities remain one default buffer.
    it("testBufferDefaultTwiceFused", check_buffer(64, function (source) return source:buffer():buffer() end))
    -- adapted: explicit capacity replaces default capacity during fusion.
    it("testBufferDefaultBufferFused", check_buffer(7, function (source) return source:buffer():buffer(7) end))
    -- adapted: explicit capacity takes precedence over a following default.
    it("testBufferBufferDefaultFused", check_buffer(8, function (source) return source:buffer(8):buffer() end))
    it(
        "testFlowOnNameNoBuffer",
        check_buffer(-1, function (source)
            return source:flow_on(async.context(async.coroutine_name("Name")))
        end)
    )
    -- not-applicable: luastd has no dispatcher context element.
    pending("testFlowOnDispatcherBufferDefault")
    -- not-applicable: luastd has no dispatcher context element.
    pending("testFlowOnDispatcherBufferFused")
    -- not-applicable: luastd has no dispatcher context element.
    pending("testBufferFlowOnDispatcherFused")
    -- adapted: CoroutineName does not dispatch, so the explicit buffer is fused.
    it(
        "testFlowOnNameBufferFused",
        check_buffer(7, function (source)
            return source:flow_on(async.context(async.coroutine_name("Name"))):buffer(7)
        end)
    )
    -- adapted: CoroutineName does not dispatch, so the explicit buffer is fused.
    it(
        "testBufferFlowOnNameFused",
        check_buffer(8, function (source)
            return source:buffer(8):flow_on(async.context(async.coroutine_name("Name")))
        end)
    )
    -- not-applicable: the test requires a dispatcher context element.
    pending("testBufferFlowOnMultipleFused")
    it(
        "testCancellation",
        runtest(function (t)
            local result = flow.new(function (emit)
                emit(1)
                emit(2)
                t:expect_unreached()
                emit(3)
            end):buffer(0):take(2):to_list()
            assert.is_equal(2, #result)
            assert.is_equal(1, result[1])
            assert.is_equal(2, result[2])
        end)
    )
    -- adapted: Flow:buffer has no BufferOverflow parameter, so the Kotlin-only
    -- invalid CONFLATED/overflow combinations cannot be represented; verify
    -- the invalid negative capacities supported by this API.
    it("testFailsOnIllegalArguments", function ()
        for _, cap in ipairs({ -3, -2147483648 }) do
            local ok, err = pcall(function () flow.empty():buffer(cap):to_list() end)
            assert.is_false(ok)
            assert.is_equal("InvalidArgument", err.kind)
        end
    end)
end)
