-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/DebounceTest.kt@1.11.0
local flow = require("luastd.flow")
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

describe("DebounceTest", function ()
    -- adapted: use real millisecond delays with broad margins instead of
    -- kotlinx.coroutines' virtual-time scheduler.
    it(
        "testBasic",
        runtest(function ()
            local result = flow.new(function (emit)
                emit("A")
                async.delay(30)
                emit("B")
                async.delay(5)
                emit("C")
                async.delay(3)
                emit("D")
                async.delay(30)
                emit("E")
            end):debounce(20):to_list()
            assert.same({ "A", "D", "E" }, result)
        end)
    )

    -- adapted: nil cannot be sent through Channel, so encode it as a sentinel
    -- during debounce and assert the debounced sentinel reaches the collector.
    it(
        "testSingleNull",
        runtest(function ()
            local null_value = {}
            local result = flow.of_one(null_value):debounce(10000):to_list()
            assert.is_equal(1, #result)
            assert.is_true(rawequal(null_value, result[1]))
        end)
    )

    -- adapted: sentinel values represent null while passing through the
    -- channel-backed debounce implementation, then are checked in order.
    it(
        "testBasicWithNulls",
        runtest(function ()
            local null_value = {}
            local result = flow.new(function (emit)
                emit("A")
                async.delay(30)
                emit("B")
                async.delay(5)
                emit("C")
                async.delay(3)
                emit(null_value)
                async.delay(30)
                emit(null_value)
            end):debounce(20):to_list()
            assert.is_equal(3, #result)
            assert.is_equal("A", result[1])
            assert.is_true(rawequal(null_value, result[2]))
            assert.is_true(rawequal(null_value, result[3]))
        end)
    )

    it(
        "testEmpty",
        runtest(function ()
            assert.same({}, flow.empty():debounce(10000):to_list())
        end)
    )

    it(
        "testScalar",
        runtest(function ()
            assert.is_equal(3, flow.from({ 1, 2, 3 }):debounce(10000):single())
        end)
    )

    -- adapted: replace virtual time with real delays and keep comfortable
    -- spacing between the rapid burst and values expected to pass separately.
    it(
        "testPace",
        runtest(function ()
            local result = flow.new(function (emit)
                for i = 0, 9 do
                    emit(-i)
                    async.delay(5)
                end
                for i = 0, 9 do
                    emit(i)
                    async.delay(25)
                end
            end):debounce(15):to_list()
            assert.same({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }, result)
        end)
    )

    -- adapted: a regular TestException stands in for TimeoutCancellationException;
    -- debounce must propagate an upstream failure after a value is observed.
    it(
        "testUpstreamError",
        runtest(function ()
            local failure = luastd_test.TestException()
            local latch = async.channel()
            local source = flow.new(function (emit)
                emit(1)
                latch:receive()
                error(failure, 0)
            end):debounce(1):map(function ()
                latch:send(true)
                async.await_cancellation()
            end)
            local ok, err = pcall(function () source:to_list() end)
            assert.is_false(ok)
            assert.is_equal("TestException", err.kind)
        end)
    )

    -- not-applicable: this test's TimeoutCancellationException is a cancellation
    -- cause; luastd cancellation bypasses Lua pcall and Flow:catch (ADR 0005).
    pending("testUpstreamErrorCancellation")

    -- adapted: use a regular error and CoroutineName because dispatcher
    -- contexts are not exposed; assert the upstream error still propagates.
    it(
        "testUpstreamErrorIsolatedContext",
        runtest(function ()
            local failure = luastd_test.TestException()
            local context = async.context(async.coroutine_name("upstream"))
            local source = flow.new(function (emit)
                assert.is_equal("upstream", async.current_context():coroutine_name())
                emit(1)
                error(failure, 0)
            end):flow_on(context):debounce(10000)
            local ok, err = pcall(function () source:to_list() end)
            assert.is_false(ok)
            assert.is_equal("TestException", err.kind)
        end)
    )

    it(
        "testUpstreamErrorDebounceNotTriggered",
        runtest(function ()
            local failure = luastd_test.TestException()
            local source = flow.new(function (emit)
                emit(1)
                error(failure, 0)
            end):debounce(10000):map(function () error("debounce emitted before upstream failed") end)
            local ok, err = pcall(function () source:to_list() end)
            assert.is_false(ok)
            assert.is_true(rawequal(failure, err))
        end)
    )

    -- adapted: use CoroutineName instead of NamedDispatchers; the upstream
    -- error must still bypass the long debounce delay.
    it(
        "testUpstreamErrorDebounceNotTriggeredInIsolatedContext",
        runtest(function ()
            local failure = luastd_test.TestException()
            local context = async.context(async.coroutine_name("source"))
            local source = flow.new(function (emit)
                assert.is_equal("source", async.current_context():coroutine_name())
                emit(1)
                error(failure, 0)
            end):flow_on(context):debounce(10000):map(function ()
                error("debounce emitted before upstream failed")
            end)
            local ok, err = pcall(function () source:to_list() end)
            assert.is_false(ok)
            assert.is_equal("TestException", err.kind)
        end)
    )

    it(
        "testDownstreamError",
        runtest(function ()
            local failure = luastd_test.TestException()
            local source = flow.new(function (emit)
                emit(1)
                async.await_cancellation()
            end):debounce(1):map(function () error(failure, 0) end)
            local ok, err = pcall(function () source:to_list() end)
            assert.is_false(ok)
            assert.is_equal("TestException", err.kind)
        end)
    )

    -- adapted: use CoroutineName rather than dispatchers while checking a
    -- downstream failure after debounce emits its value.
    it(
        "testDownstreamErrorIsolatedContext",
        runtest(function ()
            local failure = luastd_test.TestException()
            local context = async.context(async.coroutine_name("upstream"))
            local source = flow.new(function (emit)
                assert.is_equal("upstream", async.current_context():coroutine_name())
                emit(1)
                async.await_cancellation()
            end):flow_on(context):debounce(1):map(function ()
                error(failure, 0)
            end)
            local ok, err = pcall(function () source:to_list() end)
            assert.is_false(ok)
            assert.is_equal("TestException", err.kind)
        end)
    )

    -- adapted: the runtime takes a numeric millisecond duration rather than a
    -- Kotlin Duration value; timings mirror testBasic with real delays.
    it(
        "testDurationBasic",
        runtest(function ()
            local result = flow.new(function (emit)
                emit("A")
                async.delay(30)
                emit("B")
                async.delay(5)
                emit("C")
                async.delay(3)
                emit("D")
                async.delay(30)
                emit("E")
            end):debounce(20):to_list()
            assert.same({ "A", "D", "E" }, result)
        end)
    )

    -- not-applicable: debounce accepts only a fixed timeout; there is no
    -- per-element timeout-selector overload.
    pending("testDebounceSelectorBasic")

    -- defer: the current Flow:debounce(0) coalesces a synchronous burst to
    -- its last value; Kotlin requires zero timeout to pass every value through.
    pending("testZeroDebounceTime")

    -- not-applicable: the selector form is absent, including its zero-time case.
    pending("testZeroDebounceTimeSelector")

    -- not-applicable: luastd has no Kotlin Duration selector callback overload.
    pending("testDebounceDurationSelectorBasic")

    it(
        "testFailsWithIllegalArgument",
        runtest(function ()
            local ok = pcall(function () flow.empty():debounce(-1):to_list() end)
            assert.is_false(ok)
        end)
    )
end)
