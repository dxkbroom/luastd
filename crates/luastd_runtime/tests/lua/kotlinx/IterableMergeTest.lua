-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/MergeTest.kt@1.11.0
local async = require("luastd.async")
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

describe("IterableMergeTest", function ()
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

    it(
        "testSingle",
        runtest(function ()
            local result = flow.merge({ flow.empty(), flow.of_one(42), flow.empty() }):to_list()
            assert.same({ 42 }, result)
        end)
    )

    -- adapted: merge now transports tagged events through its internal Channel;
    -- callback counts verify null values without storing them in a Lua array.
    it(
        "testNulls",
        runtest(function ()
            local left = flow.new(function (emit)
                emit(1)
                emit(nil)
            end)
            local right = flow.new(function (emit)
                emit(nil)
                emit(2)
            end)
            local ones, twos, nulls = 0, 0, 0
            flow.merge({ left, right }):collect(function (value)
                if value == nil then
                    nulls = nulls + 1
                elseif value == 1 then
                    ones = ones + 1
                elseif value == 2 then
                    twos = twos + 1
                else
                    error("unexpected merged value: " .. tostring(value))
                end
            end)
            assert.is_equal(1, ones)
            assert.is_equal(1, twos)
            assert.is_equal(2, nulls)
        end)
    )

    -- adapted: use CoroutineName instead of NamedDispatchers to check that a
    -- source's flow_on context is preserved through iterable merge.
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
    -- merge continues; luastd cancellation bypasses the source completion
    -- path (ADR 0005), and flow.merge closes its channel on normal completion.
    pending("testOneSourceCancelled")

    -- not-applicable: the non-fused variant uses channelFlow and launch per
    -- source, which luastd does not expose; cancellation is also uncatchable.
    pending("testOneSourceCancelledNonFused")

    -- adapted: verify source CoroutineName values survive concurrent merge
    -- under a different outer collection context; dispatcher isolation itself
    -- is not exposed by luastd.
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
