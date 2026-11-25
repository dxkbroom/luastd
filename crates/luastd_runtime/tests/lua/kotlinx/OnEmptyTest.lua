-- Port of kotlinx.coroutines' OnEmptyTest.

local async = require("luastd.async")
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/OnEmptyTest.kt@1.11.0
describe("OnEmptyTest", function ()
    -- adapted: Flow:on_empty has no emitter parameter, so it can assert callback
    -- invocation but cannot reproduce Kotlin's emitted value 1.
    it("testOnEmptyInvoked", runtest(function ()
        local invoked = false
        local r = flow.empty():on_empty(function () invoked = true end):to_list()
        assert.is_true(invoked)
        assert.is_equal(0, #r)
    end))

    it("testOnEmptyNotInvoked", runtest(function ()
        local invoked = false
        local r = flow.from({ 1 }):on_empty(function () invoked = true end):to_list()
        assert.is_false(invoked)
        assert.is_equal(1, #r)
    end))

    it("testOnEmptyNotInvokedOnError", runtest(function ()
        local failure = luastd_test.TestException()
        local invoked = false
        local source = flow.new(function () error(failure, 0) end):on_empty(function () invoked = true end)
        local ok, err = pcall(function () source:to_list() end)
        assert.is_false(ok)
        assert.is_true(rawequal(failure, err))
        assert.is_false(invoked)
    end))

    -- adapted: cancellation bypasses the callback and runs the upstream
    -- structured child's cancellation hook before collection joins.
    it("testOnEmptyNotInvokedOnCancellation", runtest(function (t)
        local invoked = false
        local job = async.launch(function ()
            local source = flow.new(function ()
                async.scope(function (scope)
                    local child = scope:launch(function () async.await_cancellation() end)
                    child:on_cancel(function () t:expect(4) end)
                    t:expect(2)
                    async.await_cancellation()
                end)
            end):on_empty(function () invoked = true end)
            source:collect(function () t:expect_unreached() end)
        end)
        t:expect(1)
        async.yield()
        t:expect(3)
        job:cancel()
        async.join(job)
        assert.is_false(invoked)
        t:finish(5)
    end))

    -- adapted: the callback is reached on the empty path and suspends until
    -- collector cancellation; its post-suspension emission must not run.
    it("testOnEmptyCancellation", runtest(function (t)
        local callback_invoked = false
        local collected = false
        local job = async.launch(function ()
            flow.empty():on_empty(function ()
                callback_invoked = true
                t:expect(2)
                async.await_cancellation()
            end):collect(function () collected = true end)
        end)
        job:on_cancel(function () t:expect(4) end)
        t:expect(1)
        async.yield()
        t:expect(3)
        job:cancel()
        async.join(job)
        assert.is_true(callback_invoked)
        assert.is_false(collected)
        t:finish(5)
    end))

    -- defer: on_empty receives no emitter and the API does not enforce
    -- Kotlin Flow's same-coroutine emission transparency rule.
    pending("testTransparencyViolation")
end)
