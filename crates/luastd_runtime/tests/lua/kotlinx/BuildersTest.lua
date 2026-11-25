-- Port of kotlinx.coroutines' BuildersTest (flow).
-- luastd uses flow.from({values}) instead of asFlow extensions on ranges/sequences/arrays.
-- kotlin: kotlinx-coroutines-core/common/test/flow/BuildersTest.kt@1.11.0
describe("BuildersTest", function ()
    -- not-applicable: Kotlin asFlow extensions on ranges/sequences/arrays/lambdas have no Lua equivalent; use flow.from.
    pending("testSuspendLambdaAsFlow")

    -- not-applicable: Kotlin IntRange/LongRange asFlow; use flow.from with a table.
    pending("testRangeAsFlow")

    -- not-applicable: Kotlin array asFlow; use flow.from with a table.
    pending("testArrayAsFlow")

    -- not-applicable: Kotlin Iterable/Iterator asFlow; use flow.from with a table.
    pending("testSequence")
end)
