-- Port of kotlinx.coroutines' DropWhileTest.
local async = require("luastd.async")
local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

local function sum(source)
    return source:fold(0, function (acc, value) return acc + value end)
end

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/DropWhileTest.kt@1.11.0
describe("DropWhileTest", function ()
    it("testDropWhile", runtest(function ()
        local source = flow.from({ 1, 2, 3 })
        assert.is_equal(6, sum(source:drop_while(function () return false end)))
        assert.same({}, source:drop_while(function () return true end):to_list())
        assert.is_equal(5, sum(source:drop_while(function (value) return value < 2 end)))
        assert.is_equal(1, source:take(1):drop_while(function (value) return value > 1 end):single())
    end))

    it("testEmptyFlow", runtest(function ()
        assert.is_equal(0, sum(flow.empty():drop_while(function () return true end)))
        assert.is_equal(0, sum(flow.empty():drop_while(function () return false end)))
    end))

    -- adapted: use a structured child cancellation hook to observe the upstream
    -- cleanup that Kotlin's ATOMIC child records from its finally block.
    it("testErrorCancelsUpstream", runtest(function (t)
        local failure = luastd_test.TestException()
        local source = flow.new(function (emit)
            async.scope(function (scope)
                local child = scope:launch(function () async.delay(math.huge) end)
                child:on_cancel(function () t:expect(4) end)
                t:expect(2)
                emit(1)
                t:expect_unreached()
            end)
        end):drop_while(function ()
            t:expect(3)
            error(failure, 0)
        end)

        t:expect(1)
        local ok, err = pcall(function () sum(source) end)
        assert.is_false(ok)
        assert.is_true(rawequal(failure, err), tostring(err))
        t:finish(5)
    end))
end)
