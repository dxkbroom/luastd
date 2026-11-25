-- kotlin: kotlinx-coroutines-core/common/test/flow/sharing/ShareInFusionTest.kt@1.11.0
local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

describe("ShareInFusionTest", function ()
    it("testOperatorFusion", runtest(function (t)
        local shared = flow.empty():share_in(async.current())
        assert.is_nil(shared.emit)
        assert.is_true(shared == shared:cancellable())
        assert.is_true(shared == shared:flow_on(async.context(async.coroutine_name("ignored"))))
        assert.is_true(shared == shared:buffer(0))
        t:finish(1)
    end))

    -- adapted: flow.new plus buffer(10) exercises buffered upstream collection;
    -- channel_flow's trySend builder API is not modeled.
    it("testFlowOnContextFusion", runtest(function (t)
        local owner = async.supervisor_job()
        local started = async.channel(1)
        local cleaned = async.channel(1)
        local source = flow.new(function (emit)
            assert.is_equal("FlowCtx", async.current_context():coroutine_name())
            async.finally(function ()
                emit("OK")
                started:send(true)
                async.await_cancellation()
            end, function ()
                cleaned:send(true)
            end)
        end):flow_on(async.context(async.coroutine_name("FlowCtx")))
        async.launch(async.context(owner), function (scope)
            local shared = source:share_in(scope, 1)
            assert.is_equal("OK", shared:first())
            async.await_cancellation()
        end)
        started:receive()
        owner:cancel()
        assert.is_true(cleaned:receive())
        t:finish(1)
    end))

    -- adapted: flow.new plus buffer(10) preserves the buffered-upstream behavior;
    -- channel_flow and its trySend result type are not modeled.
    it("testChannelFlowBufferShareIn", runtest(function (t)
        t:expect(1)
        local source = flow.new(function (emit)
            for i = 1, 10 do emit(i) end
            emit(0)
        end):buffer(10)
        local received = {}
        local tenth = async.channel(1)
        local shared = source:share_in(async.current())
        local subscriber = async.launch(function ()
            shared:collect(function (i)
                if i > 0 then
                    received[#received + 1] = i
                    t:expect(i + 1)
                    if i == 10 then tenth:send(true) end
                end
            end)
        end)
        tenth:receive()
        subscriber:cancel()
        async.yield()
        assert.same({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, received)
        t:finish(12)
    end))
end)
