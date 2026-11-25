-- kotlin: kotlinx-coroutines-core/common/test/selects/SelectBiasTest.kt@1.11.0
describe("SelectBiasTest", function ()
    -- not-applicable: luastd has no select/select_unbiased expression or
    -- deferred on_await clauses, so it cannot measure clause selection bias.
    pending("testBiased")
    pending("testUnbiased")
end)
