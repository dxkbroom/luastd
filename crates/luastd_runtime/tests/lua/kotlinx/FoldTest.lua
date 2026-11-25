-- Port of kotlinx.coroutines' FoldTest.
local async = require("luastd.async")
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/FoldTest.kt@1.11.0
describe("FoldTest", function ()
    it("testFold", runtest(function ()
        local source = flow.from({ 1, 2 })
        assert.is_equal(6, source:fold(3, function (acc, value) return value + acc end))
    end))

    it("testEmptyFold", runtest(function ()
        assert.is_equal(42, flow.empty():fold(42, function (acc, value) return value + acc end))
    end))

    -- adapted: async.scope and the child's cancellation hook model the upstream
    -- structured child and its cancellation finalizer.
    it("testErrorCancelsUpstream", runtest(function (t)
        local latch = async.channel(0)
        local failure = luastd_test.TestException()
        local source = flow.new(function (emit)
            async.scope(function (scope)
                local child = scope:launch(function ()
                    t:expect(3)
                    latch:send(true)
                    async.delay(math.huge)
                end)
                child:on_cancel(function () t:expect(5) end)
                t:expect(2)
                emit(1)
            end)
        end)

        t:expect(1)
        local ok, err = pcall(function ()
            source:fold(42, function ()
                latch:receive()
                t:expect(4)
                error(failure, 0)
            end)
        end)
        assert.is_false(ok)
        assert.is_true(rawequal(failure, err))
        t:finish(6)
    end))
end)
