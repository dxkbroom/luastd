-- A busted-shaped harness for specs that need luastd_runtime (async, effect
-- modules). busted itself needs `io` and `lfs`, which the sandbox removes.
-- Supports describe/it/pending, before_each, and the luassert subset used here.
-- Each `it` runs as plain code in the spec's coroutine, so `---@async`
-- functions can be called directly.

local tests, prefix = {}, {}
---@type (fun())[][]
local hooks = {}

local function describe(name, body)
    table.insert(prefix, name)
    table.insert(hooks, {})
    body()
    table.remove(hooks)
    table.remove(prefix)
end

local function before_each(fn)
    local level = hooks[#hooks]
    if not level then error("before_each outside describe", 2) end
    table.insert(level, fn)
end

local function it(name, body)
    local before = {}
    for _, level in ipairs(hooks) do
        for _, fn in ipairs(level) do
            table.insert(before, fn)
        end
    end
    table.insert(tests, { name = table.concat(prefix, " ") .. " " .. name, body = body, before = before })
end

--- Declare a test that is not run; it is counted as skipped. As in busted, a
--- function argument is ignored. Kotlin ports put the reason in a
--- `-- not-applicable:`, `-- defer:`, or `-- todo:` comment above it (AGENTS.md).
local function pending(name)
    table.insert(tests, { name = table.concat(prefix, " ") .. " " .. name, pending = true })
end

local function fail(message, level)
    error(message, (level or 1) + 2)
end

local function show(value)
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end

local function same(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for key, value in pairs(a) do
        if not same(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

-- Lua's own assert; the analyzer only knows the luassert global.
local raw_assert = assert --[[@as fun(v: any, message?: any, ...: any): any]]
local check = {}

function check.is_equal(expected, actual)
    if expected ~= actual then fail("expected " .. show(expected) .. ", got " .. show(actual)) end
end

function check.same(expected, actual)
    if not same(expected, actual) then fail("tables differ") end
end

function check.is_true(value)
    if value ~= true then fail("expected true, got " .. show(value)) end
end

function check.is_false(value)
    if value ~= false then fail("expected false, got " .. show(value)) end
end

function check.is_nil(value)
    if value ~= nil then fail("expected nil, got " .. show(value)) end
end

function check.is_not_nil(value)
    if value == nil then fail("expected a value, got nil") end
end

function check.matches(pattern, text, init, plain)
    if type(text) ~= "string" or not string.find(text, pattern, init or 1, plain) then
        fail("expected " .. show(text) .. " to match " .. show(pattern))
    end
end

function check.has_error(fn)
    local ok = pcall(fn)
    if ok then fail("expected an error") end
end

check.are = { same = check.same, equal = check.is_equal }

local assert_table = setmetatable(check, {
    __call = function (_, ...) return raw_assert(...) end
})

-- rawset keeps the analyzer on busted's own types for these globals.
rawset(_G, "describe", describe)
rawset(_G, "it", it)
rawset(_G, "pending", pending)
rawset(_G, "before_each", before_each)
rawset(_G, "assert", assert_table)

--- Run every registered test; returns passed count, failure messages and
--- the number of pending tests.
---@return integer passed
---@return string[] failures
---@return integer skipped
local function run()
    local passed, failures, skipped = 0, {}, 0
    for _, test in ipairs(tests) do
        if test.pending then
            skipped = skipped + 1
        else
            local ok, err = pcall(function ()
                for _, fn in ipairs(test.before) do
                    fn()
                end
                test.body()
            end)
            if ok then
                passed = passed + 1
            else
                table.insert(failures, test.name .. ": " .. tostring(err))
            end
        end
    end
    return passed, failures, skipped
end

return run
