-- Port of kotlinx.coroutines' CountTest.
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

local function assert_failure(source, predicate)
    local checked = predicate and source:filter(predicate) or source
    local ok, err = pcall(function () checked:count() end)
    assert.is_false(ok)
    return err
end

-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/CountTest.kt@1.11.0
describe("CountTest", function ()
    -- adapted: Flow:count has no predicate overload; compose filter and count.
    it("testCount", runtest(function ()
        local source = flow.from({ 239, 240 })
        assert.is_equal(2, source:count())
        assert.is_equal(2, source:filter(function () return true end):count())
        assert.is_equal(1, source:filter(function (value) return value % 2 == 0 end):count())
        assert.is_equal(0, source:filter(function () return false end):count())
    end))

    -- adapted: exercise predicate counts as filter(predicate):count().
    it("testNoValues", runtest(function ()
        local source = flow.empty()
        assert.is_equal(0, source:count())
        assert.is_equal(0, source:filter(function () return false end):count())
        assert.is_equal(0, source:filter(function () return true end):count())
    end))

    -- adapted: the predicate overload is represented with filter(false); assert
    -- that both forms preserve the thrown TestException identity.
    it("testException", runtest(function ()
        local failure = require("luastd_test").TestException()
        local source = flow.new(function () error(failure, 0) end)
        assert.is_true(rawequal(failure, assert_failure(source)))
        assert.is_true(rawequal(failure, assert_failure(source, function () return false end)))
    end))

    -- adapted: count(predicate) is expressed as filter(predicate):count().
    it("testExceptionAfterValue", runtest(function ()
        local failure = require("luastd_test").TestException()
        local source = flow.new(function (emit)
            emit(1)
            error(failure, 0)
        end)
        assert.is_true(rawequal(failure, assert_failure(source)))
        assert.is_true(rawequal(failure, assert_failure(source, function () return false end)))
    end))
end)
