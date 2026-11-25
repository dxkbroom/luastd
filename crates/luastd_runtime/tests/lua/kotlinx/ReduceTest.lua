-- Port of kotlinx.coroutines' ReduceTest.
local async = require("luastd.async")
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/ReduceTest.kt@1.11.0
describe("ReduceTest", function ()
    it("testReduce", runtest(function ()
        local source = flow.from({ 1, 2 })
        assert.is_equal(3, source:reduce(function (acc, value) return value + acc end))
    end))

    -- adapted: empty reduce raises a descriptive Lua error string rather than
    -- a NoSuchElementException object.
    it("testEmptyReduce", runtest(function ()
        local ok, err = pcall(function ()
            flow.empty():reduce(function (acc, value) return value + acc end)
        end)
        assert.is_false(ok)
        assert.is_true(err:find("reduce on empty flow", 1, true) ~= nil)
    end))

    -- adapted: emit nil directly from flow.new because Lua arrays cannot keep
    -- nil elements; reduce still receives the actual nullable values.
    it("testNullableReduce", runtest(function ()
        local invocations = 0
        local source = flow.new(function (emit)
            emit(1)
            emit(nil)
            emit(nil)
            emit(2)
        end)
        local result = source:reduce(function (_, value)
            invocations = invocations + 1
            return value
        end)
        assert.is_equal(2, result)
        assert.is_equal(3, invocations)
    end))

    -- adapted: use flow.of_one/flow.new for actual nullable source values;
    -- empty reduce reports a descriptive Lua error string rather than a typed
    -- NoSuchElementException.
    it("testReduceNulls", runtest(function ()
        assert.is_nil(flow.of_one(nil):reduce(function (_, value) return value end))
        local two_nulls = flow.new(function (emit)
            emit(nil)
            emit(nil)
        end)
        assert.is_nil(two_nulls:reduce(function (_, value) return value end))
        local ok, err = pcall(function ()
            flow.empty():reduce(function (_, value) return value end)
        end)
        assert.is_false(ok)
        assert.is_true(err:find("reduce on empty flow", 1, true) ~= nil)
    end))

    -- adapted: async.scope and a child cancellation hook model the upstream
    -- cleanup performed when the downstream reducer throws.
    it("testErrorCancelsUpstream", runtest(function ()
        local latch = async.channel(0)
        local cancelled = false
        local failure = luastd_test.TestException()
        local source = flow.new(function (emit)
            async.scope(function (scope)
                local child = scope:launch(function ()
                    latch:send(true)
                    async.delay(math.huge)
                end)
                child:on_cancel(function () cancelled = true end)
                emit(1)
                emit(2)
            end)
        end)

        local ok, err = pcall(function ()
            source:reduce(function ()
                latch:receive()
                error(failure, 0)
            end)
        end)
        assert.is_false(ok)
        assert.is_true(rawequal(failure, err))
        assert.is_true(cancelled)
    end))
end)
