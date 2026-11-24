-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/CancellableTest.kt@1.11.0
local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

describe("CancellableTest", function ()
    it(
        "testCancellable",
        runtest(function ()
            local values = {}
            for i = 0, 1000 do
                values[#values + 1] = i
            end
            ---@type number
            local sum = 0
            local source = flow.from(values):on_each(function (i)
                if i ~= 0 then async.current():cancel() end
                sum = sum + i
            end)
            local job = async.launch(function ()
                source:collect(function () end)
            end)
            async.join(job)
            assert.is_equal(500500, sum)

            sum = 0
            job = async.launch(function ()
                source:cancellable():collect(function () end)
            end)
            async.join(job)
            assert.is_equal(1, sum)
        end)
    )

    it("testFastPath", function ()
        local list_flow = flow.from({ 1 })
        assert.is_false(rawequal(list_flow, list_flow:cancellable()))

        local cancellable_flow = flow.new(function (emit) emit(42) end)
        assert.is_true(rawequal(cancellable_flow, cancellable_flow:cancellable()))
    end)
end)
