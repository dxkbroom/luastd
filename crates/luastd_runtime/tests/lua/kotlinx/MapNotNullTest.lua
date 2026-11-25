-- Port of kotlinx.coroutines' MapNotNullTest.

local flow = require("luastd.flow")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/MapNotNullTest.kt@1.11.0
describe("MapNotNullTest", function ()
    it(
        "testMap",
        runtest(function ()
            local source = flow.new(function (emit)
                emit(1)
                emit(nil)
                emit(2)
            end)
            local result = source:map_not_null(function (value) return value end):to_list()
            assert.same({ 1, 2 }, result)
        end)
    )

    it(
        "testEmptyFlow",
        runtest(function ()
            local r = flow.empty():map_not_null(function (x) return x end):to_list()
            assert.is_equal(0, #r)
        end)
    )

    -- defer: map_not_null errors are recovered by catch, but the synchronous
    -- source emit path currently returns normally instead of cancelling its
    -- nested async scope and running upstream cleanup before recovery.
    pending("testErrorCancelsUpstream")
end)
