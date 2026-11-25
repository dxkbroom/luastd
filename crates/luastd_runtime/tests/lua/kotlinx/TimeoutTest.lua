-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/TimeoutTest.kt@1.11.0
local async = require("luastd.async")
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("TimeoutTest", function ()
    it(
        "testBasic",
        runtest(function (t)
            t:expect(1)
            local values = {}
            local source = flow.new(function (emit)
                t:expect(3)
                emit("A")
                async.delay(10)
                emit("B")
                async.delay(10)
                emit("C")
                t:expect(4)
                async.delay(100)
                t:expect_unreached()
            end):timeout(40)

            t:expect(2)
            local ok, err = pcall(function ()
                source:collect(function (value) table.insert(values, value) end)
            end)
            assert.is_false(ok)
            assert.is_equal("Timeout", err.kind)
            assert.same({ "A", "B", "C" }, values)
            t:finish(5)
        end)
    )

    it(
        "testSingleNull",
        runtest(function (t)
            local source = flow.new(function (emit)
                emit(nil)
                async.delay(5)
                t:expect(1)
            end):timeout(40)

            assert.is_nil(source:single())
            t:finish(2)
        end)
    )

    it(
        "testBasicCustomAction",
        runtest(function ()
            local values = flow.new(function (emit)
                emit("A")
                async.delay(10)
                emit("B")
                async.delay(10)
                emit("C")
                async.delay(100)
            end):timeout(40):catch(function (emit, err)
                if err.kind == "Timeout" then
                    emit("-1")
                else
                    error(err, 0)
                end
            end):to_list()

            assert.same({ "A", "B", "C", "-1" }, values)
        end)
    )

    it(
        "testDelayedFirst",
        runtest(function (t)
            t:expect(1)
            local source = flow.new(function (emit)
                t:expect(3)
                async.delay(5)
                emit(1)
                t:expect(4)
            end):timeout(40)

            t:expect(2)
            assert.is_equal(1, source:single())
            t:finish(5)
        end)
    )

    -- adapted: Flow has no single_or_null terminal; an empty list asserts that
    -- an empty upstream completes before its inactivity timeout.
    it(
        "testEmpty",
        runtest(function ()
            local values = flow.empty():timeout(40):to_list()
            assert.same({}, values)
        end)
    )

    it(
        "testScalar",
        runtest(function ()
            local values = flow.from({ 1, 2, 3 }):timeout(40):to_list()
            assert.same({ 1, 2, 3 }, values)
        end)
    )

    it(
        "testUpstreamError",
        runtest(function ()
            local failure = luastd_test.TestException()
            local source = flow.new(function (emit)
                emit(1)
                error(failure, 0)
            end):timeout(40)
            local ok, err = pcall(function () source:to_list() end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
        end)
    )

    it(
        "testUpstreamErrorTimeoutException",
        runtest(function ()
            local ok, upstream_timeout = pcall(function ()
                async.with_timeout(0, function () end)
            end)
            assert.is_false(ok)
            local source = flow.new(function (emit)
                emit(1)
                error(upstream_timeout, 0)
            end):timeout(40)
            local collected, err = pcall(function () source:to_list() end)
            assert.is_false(collected)
            assert.is_true(rawequal(upstream_timeout, err))
        end)
    )

    -- not-applicable: Kotlin's CancellationException is cancellation; luastd
    -- cancellation is uncatchable by user code (ADR 0005).
    pending("testUpstreamErrorCancellationException")

    -- not-applicable: this priority case relies on NonCancellable to keep
    -- upstream running after timeout cancellation; luastd has no such context.
    pending("testUpstreamExceptionsTakingPriority")

    it(
        "testDownstreamError",
        runtest(function ()
            local failure = luastd_test.TestException()
            local source = flow.new(function (emit)
                emit(1)
                async.delay(1000)
            end):timeout(100):map(function ()
                async.yield()
                error(failure, 0)
            end)
            local ok, err = pcall(function () source:to_list() end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
        end)
    )

    it(
        "testUpstreamTimeoutIsolatedContext",
        runtest(function (t)
            local context = async.context(async.coroutine_name("upstream"))
            local source = flow.new(function (emit)
                assert.is_equal("upstream", async.current_context():coroutine_name())
                t:expect(1)
                emit(1)
                t:expect(2)
                async.delay(100)
                t:expect_unreached()
            end):flow_on(context):timeout(30)

            local ok, err = pcall(function () source:to_list() end)
            assert.is_false(ok)
            assert.is_equal("Timeout", err.kind)
            t:finish(3)
        end)
    )

    it(
        "testUpstreamTimeoutActionIsolatedContext",
        runtest(function (t)
            local context = async.context(async.coroutine_name("upstream"))
            local source = flow.new(function (emit)
                assert.is_equal("upstream", async.current_context():coroutine_name())
                t:expect(1)
                emit(1)
                t:expect(2)
                async.delay(100)
                t:expect_unreached()
            end):flow_on(context):timeout(30):catch(function (emit, err)
                assert.is_equal("Timeout", err.kind)
                t:expect(3)
                emit(2)
            end)

            assert.same({ 1, 2 }, source:to_list())
            t:finish(4)
        end)
    )

    it(
        "testSharedFlowTimeout",
        runtest(function ()
            local shared = flow.mutable_shared_flow():as_shared_flow():timeout(30)
            local ok, err = pcall(function () shared:to_list() end)
            assert.is_false(ok)
            assert.is_equal("Timeout", err.kind)
        end)
    )

    it(
        "testSharedFlowCancelledNoTimeout",
        runtest(function (t)
            local shared = flow.mutable_shared_flow()
            local received = {}
            t:expect(1)
            local consumer = async.launch(function ()
                t:expect(3)
                shared:as_shared_flow():timeout(100):collect(function (value)
                    table.insert(received, value)
                end)
                t:expect_unreached()
            end)
            local producer = async.launch(function ()
                t:expect(4)
                for value = 0, 5 do
                    async.delay(10)
                    shared:emit(value)
                end
                async.yield()
                consumer:cancel()
                t:expect(5)
            end)
            t:expect(2)
            async.join(producer)
            async.join(consumer)
            assert.same({ 0, 1, 2, 3, 4, 5 }, received)
            t:finish(6)
        end)
    )

    it(
        "testImmediateTimeout",
        runtest(function ()
            for _, ms in ipairs({ 0, -1 }) do
                local ran = false
                local source = flow.new(function () ran = true end):timeout(ms)
                local ok, err = pcall(function () source:to_list() end)
                assert.is_false(ok)
                assert.is_equal("Timeout", err.kind)
                assert.is_equal("Timed out immediately", err.message)
                assert.is_false(ran)
            end
        end)
    )

    -- adapted: luastd has no channel_flow builder; a source error checks that
    -- an infinite timeout leaves an upstream failure unchanged.
    it(
        "testClosing",
        runtest(function ()
            local failure = luastd_test.TestException()
            local source = flow.new(function () error(failure, 0) end):timeout(math.huge)
            local ok, err = pcall(function () source:collect(function () end) end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
        end)
    )
end)
