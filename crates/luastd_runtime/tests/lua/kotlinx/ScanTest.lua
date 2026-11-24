-- Port of kotlinx.coroutines' ScanTest.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/ScanTest.kt@1.11.0
describe("ScanTest", function ()
    it("testScan", function ()
        local r = flow.from({ 1, 2, 3 }):scan(0, function (a, v) return a + v end):to_list()
        assert.is_equal(4, #r)
        assert.is_equal(0, r[1])
        assert.is_equal(6, r[4])
    end)

    pending("testScanWithInitial")
    it("testFoldWithInitial", function ()
        local r = flow.from({ 1, 2, 3 }):scan(10, function (a, v) return a + v end):to_list()
        assert.is_equal(4, #r)
        assert.is_equal(10, r[1])
    end)

    pending("testNulls")
    it("testEmptyFlow", function ()
        local r = flow.empty():scan(5, function (a, v) return a + v end):to_list()
        assert.is_equal(1, #r)
        assert.is_equal(5, r[1])
    end)

    -- defer: error/null semantics.
    pending("testErrorCancelsUpstream")
end)
