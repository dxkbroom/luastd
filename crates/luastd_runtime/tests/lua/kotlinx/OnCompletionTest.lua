-- Port of kotlinx.coroutines' OnCompletionTest.
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/OnCompletionTest.kt@1.11.0
describe("OnCompletionTest", function ()
    it("testOnCompletion", runtest(function (t)
        local result = flow.new(function (emit)
            t:expect(1)
            emit(2)
            t:expect(4)
        end):on_each(function () t:expect(2) end):on_completion(function (err)
            assert.is_nil(err)
            t:expect(5)
        end):on_each(function () t:expect(3) end):to_list()
        assert.same({ 2 }, result)
        t:finish(6)
    end))

    it("testOnCompletionWithException", runtest(function (t)
        local failure = luastd_test.TestException()
        local result = flow.of_one(1):on_each(function ()
            t:expect(1)
            error(failure, 0)
        end):on_completion(function (err)
            assert.is_true(rawequal(failure, err))
            t:expect(2)
        end):catch(function (emit, err)
            assert.is_equal("TestException", err.kind)
            t:expect(3)
            emit("handled")
        end):to_list()
        assert.same({ "handled" }, result)
        t:finish(4)
    end))

    it("testOnCompletionWithExceptionDownstream", runtest(function (t)
        local failure = luastd_test.TestException()
        local result = flow.new(function (emit)
            t:expect(1)
            emit(2)
        end):on_each(function () t:expect(2) end):on_completion(function (err)
            assert.is_true(rawequal(failure, err))
            t:expect(4)
        end):on_each(function ()
            t:expect(3)
            error(failure, 0)
        end):catch(function (emit, err)
            assert.is_equal("TestException", err.kind)
            t:expect(5)
            emit("handled")
        end):to_list()
        assert.same({ "handled" }, result)
        t:finish(6)
    end))

    it("testMultipleOnCompletions", runtest(function (t)
        local failure = luastd_test.TestException()
        local result = flow.of_one(1):on_completion(function (err)
            assert.is_true(rawequal(failure, err))
            t:expect(2)
        end):on_each(function ()
            t:expect(1)
            error(failure, 0)
        end):on_completion(function (err)
            assert.is_true(rawequal(failure, err))
            t:expect(3)
        end):catch(function (emit, err)
            assert.is_true(rawequal(failure, err))
            t:expect(4)
            emit("handled")
        end):to_list()
        assert.same({ "handled" }, result)
        t:finish(5)
    end))

    it("testExceptionFromOnCompletion", runtest(function (t)
        local upstream_failure = luastd_test.TestException()
        local completion_failure = luastd_test.TestException2()
        local result = flow.of_one(1):on_each(function ()
            t:expect(1)
            error(upstream_failure, 0)
        end):on_completion(function ()
            t:expect(2)
            error(completion_failure, 0)
        end):catch(function (emit, err)
            assert.is_true(rawequal(completion_failure, err))
            t:expect(3)
            emit("handled")
        end):to_list()
        assert.same({ "handled" }, result)
        t:finish(4)
    end))

    -- not-applicable: the test depends on flowOn's dispatcher boundary
    -- isolating downstream errors from on_completion; luastd has no dispatchers
    -- and flow_on currently runs collection synchronously in the named context.
    pending("testContextPreservation")

    -- not-applicable: on_completion receives only an error value and cannot
    -- emit a completion marker as Kotlin's FlowCollector callback can.
    pending("testEmitExample")

    -- not-applicable: on_completion has no emit callback, so it cannot test
    -- the failure caused by trying to emit after an upstream crash.
    pending("testCrashedEmit")

    -- not-applicable: luastd cancellation bypasses Lua callbacks (ADR 0005),
    -- and on_completion has no collector emitter to attempt a cancelled emit.
    pending("testCancelledEmit")

    -- not-applicable: on_completion has no emit callback to test transparency
    -- when downstream collection has already failed.
    pending("testFailedEmit")

    -- adapted: first aborts after one value; verify on_completion observes
    -- the non-normal termination without attempting an unsupported emit.
    it("testFirst", runtest(function (t)
        local cause
        local value = flow.of_one(239):on_completion(function (err)
            cause = err
            t:expect(1)
        end):first()
        assert.is_equal(239, value)
        assert.is_not_nil(cause)
        t:finish(2)
    end))

    -- not-applicable: the Kotlin case emits a second value from on_completion;
    -- luastd's side-effect callback has no collector emitter.
    pending("testSingle")

    -- not-applicable: the callback emission that supplies an empty single()
    -- value cannot be expressed through Flow:on_completion.
    pending("testEmptySingleInterference")

    -- not-applicable: the test calls emit from a child coroutine in the
    -- completion callback; no emitter or completion scope is exposed.
    pending("testTransparencyViolation")

    -- adapted: take completes normally when it reaches its own limit; verify
    -- completion runs with a nil cause and all limited values were collected.
    it("testTakeOnCompletion", runtest(function ()
        local completed = false
        local result = flow.from({ 1, 2, 3, 4, 5, 6 }):take(5):on_completion(function (err)
            assert.is_nil(err)
            completed = true
        end):to_list()
        assert.same({ 1, 2, 3, 4, 5 }, result)
        assert.is_true(completed)
    end))

    -- not-applicable: neither completion callbacks nor flow/channel emit_all
    -- are exposed, so these tests' cancelled emitAll paths cannot be expressed.
    pending("testCancelledEmitAllFlow")
    pending("testCancelledEmitAllChannel")

    -- not-applicable: zip is absent, and take consumes the collector's early
    -- termination marker before an outer on_completion can observe it.
    pending("testOnCompletionBetweenLimitingOperators")

    -- not-applicable: the test requires on_completion to emit a replacement
    -- value after collector cancellation, but the callback has no emitter.
    pending("testEmittingElementsAfterCancellation")
end)
