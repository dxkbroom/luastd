-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/LaunchInTest.kt@1.11.0
local async = require("luastd.async")
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = require("luastd_test").runtest

describe("LaunchInTest", function ()
    -- adapted: no Flow:launch_in terminal exists; launch a coroutine that
    -- collects the same flow and join the returned Job.
    it(
        "testLaunchIn",
        runtest(function (t)
            local failure = luastd_test.TestException()
            local source = flow.new(function (emit)
                t:expect(1)
                emit(1)
                error(failure, 0)
            end):on_each(function (value)
                assert.is_equal(1, value)
                t:expect(2)
            end):on_completion(function (err)
                assert.is_true(rawequal(failure, err))
                t:expect(3)
            end):catch(function (emit, err)
                assert.is_true(rawequal(failure, err))
                t:expect(4)
            end)
            local job = async.launch(function () source:collect(function () end) end)
            async.join(job)
            t:finish(5)
        end)
    )

    -- adapted: use CoroutineName in place of NamedDispatchers when collecting
    -- the launched flow in its explicit context.
    it(
        "testDispatcher",
        runtest(function (t)
            local context = async.context(async.coroutine_name("flow"))
            local source = flow.new(function (emit)
                assert.is_equal("flow", async.current_context():coroutine_name())
                emit(1)
                t:expect(1)
            end)
            local job = async.launch(context, function () source:collect(function () end) end)
            async.join(job)
            t:finish(2)
        end)
    )

    -- adapted: async.launch is the available launched collector; runtest's
    -- expected failure observes its propagated TestException.
    it(
        "testUnhandledError",
        runtest({ expected = "TestException" }, function (t)
            local failure = luastd_test.TestException()
            local source = flow.new(function (emit)
                emit(1)
                t:expect(1)
            end):catch(function ()
                t:expect_unreached()
            end):on_completion(function ()
                t:finish(2)
                error(failure, 0)
            end)
            async.launch(function () source:collect(function () end) end)
        end)
    )
end)
