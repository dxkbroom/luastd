-- Port of kotlinx.coroutines' BufferConflationTest.

local flow = require("luastd.flow")
local async = require("luastd.async")
local runtest = require("luastd_test").runtest

-- kotlin: kotlinx-coroutines-core/common/test/flow/operators/BufferConflationTest.kt@1.11.0
describe("BufferConflationTest", function ()
    local n = 100

    local function check_conflate(t, capacity, overflow, op)
        local expected = { 0 }
        if overflow == "DROP_OLDEST" then
            for value = math.max(1, n - capacity), n - 1 do
                expected[#expected + 1] = value
            end
        else
            for value = 1, capacity do
                expected[#expected + 1] = value
            end
        end

        t:expect(1)
        local first_emitted = async.channel(0)
        local source = flow.new(function (emit)
            for value = 0, n - 1 do
                t:expect(value + 2)
                emit(value)
                if value == 0 then first_emitted:receive() end
            end
        end)
        op(source):on_each(function (value)
            if value == 0 then first_emitted:send(true) end
        end):collect(function (value)
            local index
            for i, expected_value in ipairs(expected) do
                if value == expected_value then
                    index = i - 1
                    break
                end
            end
            assert.is_not_nil(index)
            t:expect(n + 2 + index)
        end)
        t:finish(n + 2 + #expected)
    end

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testConflate",
        runtest(function (t)
            check_conflate(t, 1, "DROP_OLDEST", function (source) return source:conflate() end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testBufferConflated",
        runtest(function (t)
            check_conflate(t, 1, "DROP_OLDEST", function (source) return source:buffer(async.CONFLATED) end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testBufferDropOldest",
        runtest(function (t)
            check_conflate(t, 1, "DROP_OLDEST", function (source) return source:buffer(nil, "DROP_OLDEST") end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testBuffer0DropOldest",
        runtest(function (t)
            check_conflate(t, 1, "DROP_OLDEST", function (source) return source:buffer(0, "DROP_OLDEST") end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testBuffer1DropOldest",
        runtest(function (t)
            check_conflate(t, 1, "DROP_OLDEST", function (source) return source:buffer(1, "DROP_OLDEST") end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testBuffer10DropOldest",
        runtest(function (t)
            check_conflate(t, 10, "DROP_OLDEST", function (source) return source:buffer(10, "DROP_OLDEST") end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testConflateOverridesBuffer",
        runtest(function (t)
            check_conflate(t, 1, "DROP_OLDEST", function (source) return source:buffer(42):conflate() end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testDoubleConflate",
        runtest(function (t)
            check_conflate(t, 1, "DROP_OLDEST", function (source) return source:conflate():conflate() end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testConflateBuffer10Combine",
        runtest(function (t)
            check_conflate(t, 10, "DROP_OLDEST", function (source) return source:conflate():buffer(10) end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testBufferDropLatest",
        runtest(function (t)
            check_conflate(t, 1, "DROP_LATEST", function (source) return source:buffer(nil, "DROP_LATEST") end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testBuffer0DropLatest",
        runtest(function (t)
            check_conflate(t, 1, "DROP_LATEST", function (source) return source:buffer(0, "DROP_LATEST") end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testBuffer1DropLatest",
        runtest(function (t)
            check_conflate(t, 1, "DROP_LATEST", function (source) return source:buffer(1, "DROP_LATEST") end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testBufferDropLatestOverrideBuffer",
        runtest(function (t)
            check_conflate(t, 1, "DROP_LATEST", function (source)
                return source:buffer(42):buffer(nil, "DROP_LATEST")
            end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testBufferDropLatestOverrideConflate",
        runtest(function (t)
            check_conflate(t, 1, "DROP_LATEST", function (source)
                return source:conflate():buffer(nil, "DROP_LATEST")
            end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testBufferDropLatestBuffer7Combine",
        runtest(function (t)
            check_conflate(t, 7, "DROP_LATEST", function (source)
                return source:buffer(nil, "DROP_LATEST"):buffer(7)
            end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testConflateOverrideBufferDropLatest",
        runtest(function (t)
            check_conflate(t, 1, "DROP_OLDEST", function (source)
                return source:buffer(nil, "DROP_LATEST"):conflate()
            end)
        end)
    )

    -- adapted: a rendezvous gate substitutes for virtual-scheduler interleaving;
    -- `runtest` ordering checks remain trace assertions, not scheduler yields.
    it(
        "testBuffer3DropOldestOverrideBuffer8DropLatest",
        runtest(function (t)
            check_conflate(t, 3, "DROP_OLDEST", function (source)
                return source:buffer(8, "DROP_LATEST"):buffer(3, "DROP_OLDEST")
            end)
        end)
    )
end)
