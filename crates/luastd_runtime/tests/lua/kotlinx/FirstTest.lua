-- Port of kotlinx.coroutines' FirstTest.
-- luastd.flow is a pure-Lua cold flow; cancellation semantics differ (no
-- dispatcher), so the cancellation cases are deferred.
---@diagnostic disable: await-in-sync

local flow = require("luastd.flow")

-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/FirstTest.kt@1.11.0
describe("FirstTest", function ()
    it("testFirst", function ()
        local f = flow.from({ 1, 2, 3 })
        assert.is_equal(1, f:first())
    end)

    -- defer: luastd Flow emits Lua values; nil elements are not representable in a table.
    pending("testNulls")

    it("testFirstWithPredicate", function ()
        local f = flow.from({ 1, 2, 3 })
        assert.is_equal(1, f:first(function (x) return x > 0 end))
        assert.is_equal(2, f:first(function (x) return x > 1 end))
        local ok = pcall(function () f:first(function (x) return x > 3 end) end)
        assert.is_false(ok)
    end)

    -- defer: cancellation-driven upstream cancellation needs scheduler integration.
    pending("testFirstCancellation")

    it("testEmptyFlow", function ()
        local ok, err = pcall(function () flow.empty():first() end)
        assert.is_false(ok)
    end)

    -- defer: upstream cancellation on error requires scope integration.
    pending("testErrorCancelsUpstream")

    -- defer: firstOrNull not implemented.
    pending("testFirstOrNull")

    -- defer: firstOrNull not implemented.
    pending("testFirstOrNullWithPredicate")

    -- defer: firstOrNull not implemented.
    pending("testFirstOrNullCancellation")

    -- defer: firstOrNull not implemented.
    pending("testFirstOrNullWithEmptyFlow")

    -- defer: firstOrNull not implemented.
    pending("testFirstOrNullWithNullElement")

    -- defer: firstOrNull not implemented.
    pending("testFirstOrNullWhenErrorCancelsUpstream")

    -- not-applicable: BadClass (equals/hashCode) has no Lua equivalent.
    pending("testBadClass")

    -- defer: abort flow exception handling not yet ported.
    pending("testAbortFlowException")

    -- defer: cancellation propagation not yet ported.
    pending("testFirstThrowOnCancellation")
end)
