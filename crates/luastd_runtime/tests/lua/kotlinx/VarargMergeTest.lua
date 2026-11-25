-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/MergeTest.kt@1.11.0
local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

describe("VarargMergeTest", function ()
    -- adapted: Lua's canonical flow.merge accepts a sequence table instead of
    -- Kotlin's vararg overload; the merged values and terminal result match.
    it(
        "testMerge",
        runtest(function ()
            local sources = {}
            for value = 1, 100 do
                sources[#sources + 1] = flow.of_one(value)
            end
            local result = flow.merge(sources):to_list()
            local sum = 0
            for _, value in ipairs(result) do
                sum = sum + value
            end
            assert.is_equal(5050, sum)
        end)
    )

    -- adapted: pass the sequence to flow.merge, Lua's canonical form for the
    -- Kotlin vararg overload.
    it(
        "testSingle",
        runtest(function ()
            local result = flow.merge({ flow.empty(), flow.of_one(42), flow.empty() }):to_list()
            assert.same({ 42 }, result)
        end)
    )

    -- not-applicable: Lua nil cannot be retained as a flow value in the
    -- channel-backed merge or represented as an element of a sequence table.
    pending("testNulls")

    -- adapted: CoroutineName stands in for NamedDispatchers; the source's
    -- flow_on context remains effective through the table-based merge.
    it(
        "testContext",
        runtest(function ()
            local source_context = async.context(async.coroutine_name("source"))
            local outer_context = async.context(async.coroutine_name("irrelevant"))
            local source = flow.new(function (emit)
                emit(async.current_context():coroutine_name())
            end):flow_on(source_context)
            local result = flow.merge({ source }):flow_on(outer_context):to_list()
            assert.same({ "source" }, result)
        end)
    )

    -- not-applicable: Kotlin catches CancellationException from one source so
    -- merge continues; luastd cancellation bypasses that source completion
    -- path (ADR 0005), and flow.merge closes its channel on normal completion.
    pending("testOneSourceCancelled")

    -- not-applicable: the non-fused Kotlin variant needs channelFlow and a
    -- child launch per source, which luastd does not expose; cancellation is
    -- also uncatchable under ADR 0005.
    pending("testOneSourceCancelledNonFused")

    -- adapted: check each source's CoroutineName through flow_on; dispatcher
    -- isolation is not exposed by luastd.
    it(
        "testIsolatedContext",
        runtest(function ()
            local first = flow.new(function (emit)
                emit(async.current_context():coroutine_name())
            end):flow_on(async.context(async.coroutine_name("1")))
            local second = flow.new(function (emit)
                emit(async.current_context():coroutine_name())
            end):flow_on(async.context(async.coroutine_name("2")))
            local result = flow
                .merge({ first, second })
                :flow_on(async.context(async.coroutine_name("irrelevant")))
                :to_list()
            assert.same({ "1", "2" }, result)
        end)
    )
end)
