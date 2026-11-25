-- Port of kotlinx.coroutines' LintTest.
local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/LintTest.kt@1.11.0
describe("LintTest", function ()
    -- adapted: collect into the supplied list/set tables because Flow has no
    -- to_list(target) or to_set(target) terminal overload; yield until both
    -- scheduled collectors have subscribed instead of using Dispatchers.Unconfined.
    it("testSharedFlowToCollection", runtest(function ()
        local shared = flow.mutable_shared_flow()
        local list, set = {}, {}
        local list_job = async.launch(function ()
            shared:collect(function (value) table.insert(list, value) end)
        end)
        local set_job = async.launch(function ()
            shared:collect(function (value) set[value] = true end)
        end)
        while shared.subscription_count < 2 do async.yield() end

        for value = 0, 9 do shared:emit(value) end

        list_job:cancel()
        set_job:cancel()
        async.join(list_job)
        async.join(set_job)
        assert.same({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }, list)
        for value = 0, 9 do assert.is_true(set[value]) end
        assert.is_equal(10, (function ()
            local n = 0
            for _ in pairs(set) do n = n + 1 end
            return n
        end)())
        assert.is_equal(0, shared.subscription_count)
    end))
end)
