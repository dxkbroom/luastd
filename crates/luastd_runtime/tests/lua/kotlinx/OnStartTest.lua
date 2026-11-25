-- Port of kotlinx.coroutines' OnStartTest.
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/OnStartTest.kt@1.11.0
describe("OnStartTest", function ()
    it("testEmitExample", runtest(function ()
        local result = flow.from({ "a", "b", "c" })
            :on_start(function (emit) emit("Begin") end)
            :to_list()
        assert.same({ "Begin", "a", "b", "c" }, result)
    end))

    -- defer: on_start receives a synchronous emit callback and does not enforce
    -- Kotlin Flow's context-preserving emission rule for child coroutines.
    pending("testTransparencyViolation")
end)
