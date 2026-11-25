---@diagnostic disable: await-in-sync

local process = require("luastd.process")
local path = require("luastd.path")

---@param fn fun()
---@return luastd.Error
local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return err --[[@as luastd.Error]]
end

describe("luastd.process", function ()
    describe("run", function ()
        it("captures stdout and exit code", function ()
            local r = process.run("echo", { "hello" })
            assert.is_equal(0, r.code)
            assert.matches("hello", r.stdout)
        end)

        it("captures stderr and non-zero exit", function ()
            local r = process.run("sh", { "-c", "echo oops >&2; exit 3" })
            assert.is_equal(3, r.code)
            assert.matches("oops", r.stderr)
        end)

        it("supports cwd and env and stdin", function ()
            local r = process.run("sh", { "-c", "pwd; echo $FOO; cat" }, {
                cwd = path.new("/tmp"),
                env = { FOO = "bar" },
                stdin = "fromstdin\n"
            })
            assert.is_equal(0, r.code)
            assert.matches("/tmp", r.stdout)
            assert.matches("bar", r.stdout)
            assert.matches("fromstdin", r.stdout)
        end)
    end)

    describe("try_run", function ()
        it("returns true on success", function ()
            local ok, r = process.try_run("echo", { "hi" })
            assert.is_true(ok)
            assert.is_equal(0, r.code)
        end)
    end)

    describe("spawn", function ()
        it("exposes pid, lines, wait", function ()
            local handle = process.spawn("sh", { "-c", "printf 'line1\\nline2\\n'" })
            assert.is_not_nil(handle:pid())
            local lines = {}
            for line in handle:lines() do
                table.insert(lines, line)
            end
            assert.is_equal(2, #lines)
            assert.matches("line1", lines[1])
            assert.is_equal(0, handle:wait())
        end)

        it("kill does not error", function ()
            local handle = process.spawn("echo", { "x" })
            handle:kill()
            handle:wait()
        end)
    end)
end)
