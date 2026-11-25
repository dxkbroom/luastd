-- Port of kotlinx.coroutines' CatchTest.
local flow = require("luastd.flow")
local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = require("luastd_test").runtest

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

    it("testCatchEmitExceptionFromDownstream", function ()
        local executed = 0
        local failure = luastd_test.TestException()
        local upstream = flow.of_one(1):catch(function (emit)
            emit(42)
        end):map(function ()
            executed = executed + 1
            error(failure, 0)
        end)
        local ok, err = pcall(function () upstream:to_list() end)
        assert.is_false(ok)
        assert.is_true(rawequal(failure, err))
        assert.is_equal(1, executed)
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

    -- adapted: there is no emit_all helper; the upstream completes normally,
    -- so the catch handler does not run and the downstream failure is checked.
    it("testCatchEmitAllExceptionFromDownstream", function ()
        local executed = 0
        local failure = luastd_test.TestException()
        local upstream = flow.of_one(1):catch(function (emit)
            emit(1)
            emit(2)
            emit(3)
        end):map(function ()
            executed = executed + 1
            error(failure, 0)
        end)
        local ok, err = pcall(function () upstream:to_list() end)
        assert.is_false(ok)
        assert.is_true(rawequal(failure, err))
        assert.is_equal(1, executed)
    end)

    it(
        "testWithTimeoutCatch",
        runtest(function (t)
            local result = flow.new(function (emit)
                async.with_timeout(1, function () async.delay(math.huge) end)
                t:expect_unreached()
                emit(0)
            end):catch(function (emit, err)
                assert.is_equal("Timeout", err.kind)
                emit(1)
            end):single()
            assert.is_equal(1, result)
            t:finish(1)
        end)
    )

    it(
        "testCancellationFromUpstreamCatch",
        runtest(function (t)
            local job = async.launch(function ()
                t:expect(1)
                flow.new(function () async.await_cancellation() end)
                    :catch(function () t:expect_unreached() end)
                    :collect(function () end)
            end)
            async.yield()
            t:expect(2)
            job:cancel()
            async.join(job)
            t:finish(3)
        end)
    )

    -- adapted: luastd has no dispatcher contexts; verify CoroutineName context
    -- across flow_on and the placement of catch handlers around it.
    it(
        "testCatchContext",
        runtest(function ()
            local failure = luastd_test.TestException()
            local context_a = async.context(async.coroutine_name("A"))
            local context_b = async.context(async.coroutine_name("B"))
            local result = flow.new(function (emit)
                assert.is_equal("A", async.current_context():coroutine_name())
                emit("OK")
                error(failure, 0)
            end):catch(function (emit, err)
                assert.is_true(rawequal(failure, err))
                assert.is_equal("A", async.current_context():coroutine_name())
                error(err, 0)
            end):flow_on(context_a):catch(function (emit, err)
                assert.is_true(rawequal(failure, err))
                assert.is_equal("B", async.current_context():coroutine_name())
                error(err, 0)
            end):flow_on(context_b):catch(function (emit, err)
                assert.is_true(rawequal(failure, err))
                assert.is_nil(async.current_context():coroutine_name())
                emit("handled")
            end):to_list()
            assert.is_equal(2, #result)
            assert.is_equal("OK", result[1])
            assert.is_equal("handled", result[2])
        end)
    )

    it(
        "testUpstreamExceptionConcurrentWithDownstream",
        runtest(function (t)
            local upstream_failure = luastd_test.TestException()
            local downstream_failure = luastd_test.TestException2()
            local source = flow.new(function (emit)
                t:expect(1)
                local ok = pcall(function () emit(1) end)
                assert.is_false(ok)
                t:expect(3)
                error(upstream_failure, 0)
            end):catch(function ()
                t:expect_unreached()
            end):on_each(function ()
                t:expect(2)
                error(downstream_failure, 0)
            end)
            local ok, err = pcall(function () source:collect(function () end) end)
            assert.is_false(ok)
            assert.is_true(rawequal(upstream_failure, err))
            t:finish(4)
        end)
    )

    -- not-applicable: luastd cancellation bypasses Lua pcall and Flow:catch
    -- by ADR 0005, so these Kotlin CancellationException arbitration cases
    -- cannot be expressed with the same catchable cleanup structure.
    pending("testUpstreamExceptionConcurrentWithDownstreamCancellation")
    pending("testUpstreamCancellationIsIgnoredWhenDownstreamFails")
end)
