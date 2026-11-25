-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/SingleTest.kt@1.11.0
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest
local luastd_test = require("luastd_test")

describe("SingleTest", function ()
    -- adapted: Flow:single is covered; luastd has no single_or_null terminal
    -- operator for the second assertion in this Kotlin test.
    it("testSingle", runtest(function ()
        assert.is_equal(239, flow.of_one(239):single())
    end))

    -- adapted: verify single's multiple-value failure; the singleOrNull branch
    -- cannot be represented because luastd has no such terminal operator.
    it("testMultipleValues", runtest(function ()
        local ok = pcall(function () flow.from({ 239, 240 }):single() end)
        assert.is_false(ok)
    end))

    -- adapted: verify single's empty-flow failure; singleOrNull is absent.
    it("testNoValues", runtest(function ()
        local ok = pcall(function () flow.empty():single() end)
        assert.is_false(ok)
    end))

    it("testException", runtest(function ()
        local failure = luastd_test.TestException()
        local source = flow.new(function () error(failure) end)
        local ok, err = pcall(function () source:single() end)
        assert.is_false(ok)
        assert.is_true(rawequal(failure, err))
    end))

    it("testExceptionAfterValue", runtest(function ()
        local failure = luastd_test.TestException()
        local source = flow.new(function (emit)
            emit(1)
            error(failure)
        end)
        local ok, err = pcall(function () source:single() end)
        assert.is_false(ok)
        assert.is_true(rawequal(failure, err))
    end))

    -- not-applicable: Lua nil cannot be emitted through luastd's channel-backed
    -- flow, and the runtime also lacks Kotlin's singleOrNull terminal.
    pending("testNullableSingle")

    -- adapted: Lua tables serve as reference objects and preserve identity; the
    -- duplicate-object failure is checked with single. The singleOrNull checks
    -- in Kotlin have no corresponding luastd operator.
    it("testBadClass", runtest(function ()
        local instance = {}
        assert.is_true(rawequal(instance, flow.of_one(instance):single()))
        local ok = pcall(function () flow.from({ instance, {} }):single() end)
        assert.is_false(ok)
    end))

    -- not-applicable: Kotlin relies on singleOrNull returning after observing a
    -- second value while the upstream remains suspended in awaitCancellation;
    -- luastd has no singleOrNull, and single drains its source before returning.
    pending("testSingleNoWait")
end)
