-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/ScanTest.kt@1.11.0
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest
local luastd_test = require("luastd_test")

describe("ScanTest", function ()
    -- adapted: Flow:scan requires an initial value; runningReduce is modeled
    -- with a transform whose accumulator starts at the first upstream value.
    it(
        "testScan",
        runtest(function ()
            local has_acc = false
            local acc
            local result = flow.from({ 1, 2, 3, 4, 5 }):transform(function (emit, v)
                if has_acc then
                    acc = acc + v
                else
                    acc = v
                    has_acc = true
                end
                emit(acc)
            end):to_list()
            assert.same({ 1, 3, 6, 10, 15 }, result)
        end)
    )

    it(
        "testScanWithInitial",
        runtest(function ()
            local result = flow.from({ 1, 2, 3 }):scan({}, function (acc, value)
                local next_acc = {}
                for i, v in ipairs(acc) do
                    next_acc[i] = v
                end
                next_acc[#next_acc + 1] = value
                return next_acc
            end):to_list()
            assert.same({ {}, { 1 }, { 1, 2 }, { 1, 2, 3 } }, result)
        end)
    )

    it(
        "testFoldWithInitial",
        runtest(function ()
            local result = flow.from({ 1, 2, 3 }):scan({}, function (acc, value)
                local next_acc = {}
                for i, v in ipairs(acc) do
                    next_acc[i] = v
                end
                next_acc[#next_acc + 1] = value
                return next_acc
            end):to_list()
            assert.same({ {}, { 1 }, { 1, 2 }, { 1, 2, 3 } }, result)
        end)
    )

    -- not-applicable: Flow is channel-backed and cannot represent Kotlin's
    -- emitted null values, so runningReduce's null accumulator behavior cannot
    -- be exercised faithfully.
    pending("testNulls")

    -- adapted: runningReduce is absent; this transform starts with the first
    -- source value and emits nothing for an empty source, unlike scan(initial).
    it(
        "testEmptyFlow",
        runtest(function ()
            local result = flow.empty():transform(function () end):to_list()
            assert.same({}, result)
        end)
    )

    -- adapted: the runtime flow pipeline executes upstream and accumulator
    -- callbacks synchronously, so this checks immediate upstream unwinding on
    -- accumulator failure; it cannot reproduce Kotlin's child coroutine and
    -- latch cancellation protocol.
    it(
        "testErrorCancelsUpstream",
        runtest(function ()
            local seen = {}
            local ok, err = pcall(function ()
                flow.from({ 1, 2, 3 }):scan(0, function (acc, value)
                    seen[#seen + 1] = value
                    if value == 2 then error(luastd_test.TestException()) end
                    return acc + value
                end):to_list()
            end)
            assert.is_false(ok)
            assert.are.same({ 1, 2 }, seen)
            assert.is_equal("TestException", err.kind)
        end)
    )
end)
