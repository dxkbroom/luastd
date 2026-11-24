-- kotlin: kotlinx-coroutines-core/common/test/channels/ProduceTest.kt@1.11.0
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

local function cancel_on_completion()
    local source = async.channel()
    local produced = async.produce(function ()
        async.finally(function () source:receive() end, function () source:cancel() end)
    end)
    async.yield()
    produced:cancel()
    async.yield()
    assert.is_true(source:is_closed_for_receive())
end

describe("ProduceTest", function ()
    it(
        "testBasic",
        runtest(function (t)
            local channel = async.produce(function (producer)
                t:expect(2)
                producer:send(1)
                t:expect(3)
                producer:send(2)
                t:expect(6)
            end)
            t:expect(1)
            assert.is_equal(1, channel:receive())
            async.yield()
            t:expect(4)
            assert.is_equal(2, channel:receive())
            t:expect(5)
            async.yield()
            local ok, _, err = channel:try_receive()
            assert.is_false(ok)
            assert.is_equal("ChannelClosed", err.kind)
            t:finish(7)
        end)
    )

    -- adapted: ADR 0005 makes cancellation uncatchable, so verify that
    -- cancelling the producer channel stops its blocked send without a handler.
    it(
        "testCancelWithoutCause",
        runtest(function ()
            local reached_after_cancel = false
            local channel = async.produce(function (producer)
                producer:send(1)
                producer:send(2)
                reached_after_cancel = true
            end, 1)
            async.yield()
            channel:cancel()
            async.yield()
            assert.is_true(channel:is_closed_for_receive())
            assert.is_false(reached_after_cancel)
        end)
    )

    -- not-applicable: Channel:cancel has no cause parameter; close(cause) does
    -- not cancel the producer and therefore is not an equivalent operation.
    pending("testCancelWithCause")

    -- adapted: there is no dispatcher option; async.finally models the
    -- producer's completion cleanup and cancellation of the source channel.
    it(
        "testCancelOnCompletionUnconfined",
        runtest(function ()
            cancel_on_completion()
        end)
    )

    -- adapted: verify producer cleanup closes the source channel on cancel;
    -- luastd has no invokeOnCompletion handler or dispatcher identity.
    it(
        "testCancelOnCompletion",
        runtest(function ()
            cancel_on_completion()
        end)
    )

    -- adapted: a producer child keeps the job alive after closing its channel;
    -- cancelling the closed channel cancels that producer and its child.
    it(
        "testCancelWhenTheChannelIsClosed",
        runtest(function ()
            local child_cleanup = false
            local channel = async.produce(function (producer, scope)
                producer:send(1)
                producer:close()
                local child = scope:launch(function ()
                    async.finally(function () async.await_cancellation() end, function ()
                        child_cleanup = true
                    end)
                end)
                async.join(child)
            end)
            assert.is_equal(1, channel:receive())
            async.yield()
            channel:cancel()
            async.yield()
            assert.is_true(child_cleanup)
            assert.is_true(channel:is_closed_for_receive())
        end)
    )

    -- not-applicable: the producer API has no await_close operation or
    -- one-shot callback state for repeated await_close calls.
    pending("testAwaitCloseOnlyAllowedOnce")

    -- not-applicable: luastd channels have no invoke_on_close or await_close
    -- registration APIs.
    pending("testInvokeOnCloseWithAwaitClose")

    -- not-applicable: `await_close` and a separately attached parent Job are
    -- not exposed by async.produce.
    pending("testAwaitConsumerCancellation")

    -- not-applicable: the producer scope has no `await_close` lifetime hook or
    -- separately attached parent Job.
    pending("testAwaitProducerCancellation")

    -- not-applicable: async.produce always attaches to the current scope and
    -- has no await_close or parent Job cancellation hook.
    pending("testAwaitParentCancellation")

    -- not-applicable: there is no ProducerScope:await_close or callbackFlow
    -- builder on which to assert the Kotlin illegal-state behavior.
    pending("testAwaitIllegalState")

    -- adapted: verify an independent supervisor child can fail while the
    -- producer still sends; accept the unhandled failure explicitly.
    it(
        "testUncaughtExceptionsInProduce",
        runtest({ unhandled = { "TestException" } }, function ()
            local channel = async.produce(function (producer, scope)
                local supervisor = async.supervisor_job()
                local failure = scope:launch(async.context(supervisor), function ()
                    error(luastd_test.TestException())
                end)
                async.join(failure)
                producer:send(3)
            end)
            assert.is_equal(3, channel:receive())
        end)
    )

    -- not-applicable: the Kotlin test cancels a producer coroutine independently
    -- while keeping its channel open; luastd channel cancellation couples both.
    pending("testCancellingProduceCoroutineButNotChannel")

    -- adapted: values buffered before producer failure remain readable; unlike
    -- Kotlin, the channel itself closes without carrying the producer error.
    it(
        "testReceivingValuesAfterFailingTheCoroutine",
        runtest({ unhandled = { "TestException" } }, function ()
            async.supervisor_scope(function ()
                local channel = async.produce(function (producer)
                    for i = 0, 4 do
                        producer:send(i)
                    end
                    error(luastd_test.TestException())
                end, async.UNLIMITED)
                async.yield()
                for i = 0, 4 do
                    assert.is_equal(i, channel:receive())
                end
                local ok, err = pcall(function () channel:receive() end)
                assert.is_false(ok)
                assert.is_equal("ChannelClosed", err.kind)
            end)
        end)
    )

    -- not-applicable: the case depends on a supervisor parent that is cancelled
    -- while the producer continues sending; producer cancellation is uncatchable.
    pending("testSilentKillerInProduce")

    -- adapted: async.produce rejects invalid capacities as a structured
    -- InvalidArgument error; Lua does not expose Kotlin's exception class.
    it(
        "testProduceWithInvalidCapacity",
        runtest(function ()
            local ok, err = pcall(function () async.produce(function () end, -3) end)
            assert.is_false(ok)
            assert.is_equal("InvalidArgument", err.kind)
        end)
    )
end)
