-- kotlin: kotlinx-coroutines-core/common/test/ImmediateYieldTest.kt@1.11.0
local async = require("luastd.async")
local runtest = require("luastd_test").runtest

describe("ImmediateYieldTest", function ()
    -- adapted: luastd has no immediate dispatcher; check scheduled launch and
    -- yield ordering using the runtime's ordinary LocalSet scheduler.
    it("testImmediateYield", runtest(function (t)
        t:expect(1)
        local job = async.launch(function ()
            t:expect(3)
            async.yield()
            t:expect(5)
        end)
        t:expect(2)
        async.yield()
        t:expect(4)
        async.yield()
        async.join(job)
        t:finish(6)
    end))

    -- adapted: Dispatchers.Unconfined and dispatcher wrappers are absent;
    -- verify cooperative yield lets a normal launched child finish.
    it("testWrappedUnconfinedDispatcherYield", runtest(function (t)
        t:expect(1)
        local job = async.launch(function ()
            t:expect(3)
            async.yield()
            t:expect(4)
        end)
        t:expect(2)
        async.yield()
        async.join(job)
        t:finish(5)
    end))

    -- adapted: no unconfined wrapper exists; verify the runtime's yield path
    -- remains stack-safe through the Kotlin case's 100,000 cooperative yields.
    it("testWrappedUnconfinedDispatcherYieldStackOverflow", runtest({ timeout = 30000 }, function ()
        async.with_context(async.context(), function ()
            for _ = 1, 100000 do async.yield() end
        end)
    end))
end)
