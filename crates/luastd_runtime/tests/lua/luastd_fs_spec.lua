-- The harness runs every `it` body inside the spec's coroutine, so they may
-- call `---@async` functions.
---@diagnostic disable: await-in-sync

local fs = require("luastd.fs")
local path = require("luastd.path")

---@param fn fun()
---@return luastd.Error
local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return err --[[@as luastd.Error]]
end

---@diagnostic disable-next-line: undefined-global
local base = path.new(TEST_DIR)

describe("luastd.fs", function ()
    describe("write and read", function ()
        it("round trips a string", function ()
            local p = base / "rw.txt"
            fs.write(p, "hello")
            assert.is_equal("hello", fs.read(p))
            assert.is_equal("hello", fs.read_sync(p))
        end)

        it("try_read returns ok and value", function ()
            local p = base / "try.txt"
            fs.write(p, "x")
            local ok, v = fs.try_read(p)
            assert.is_true(ok)
            assert.is_equal("x", v)
        end)

        it("try_read returns false and FsError for missing file", function ()
            local p = base / "nope.txt"
            local ok, err = fs.try_read(p)
            assert.is_false(ok)
            assert.is_equal("FsError", err.kind)
        end)

        it("read raises FsError for missing file", function ()
            local p = base / "missing.txt"
            local err = error_of(function () fs.read(p) end)
            assert.is_equal("FsError", err.kind)
            assert.is_equal(tostring(p), err.path)
        end)
    end)

    describe("list", function ()
        it("lists entry names", function ()
            local dir = base / "listdir"
            fs.mkdir(dir)
            fs.write(dir / "a.txt", "a")
            fs.write(dir / "b.txt", "b")
            local entries = fs.list(dir)
            assert.is_true(#entries >= 2)
        end)
    end)

    describe("stat", function ()
        it("reports size and type", function ()
            local p = base / "stat.txt"
            fs.write(p, "hello")
            local info = fs.stat(p)
            assert.is_equal(5, info.size)
            assert.is_true(info.is_file)
            assert.is_false(info.is_dir)
        end)
    end)

    describe("mkdir remove rename", function ()
        it("creates, renames and removes", function ()
            local d = base / "mkrmdir"
            fs.mkdir(d)
            local info = fs.stat(d)
            assert.is_true(info.is_dir)
            local from = d / "f.txt"
            local to = d / "g.txt"
            fs.write(from, "data")
            fs.rename(from, to)
            assert.is_equal("data", fs.read(to))
            fs.remove(to)
            local ok = fs.try_read(to)
            assert.is_false(ok)
            fs.remove(d)
        end)

        it("try_write returns ok", function ()
            local p = base / "tryw.txt"
            local ok, v = fs.try_write(p, "y")
            assert.is_true(ok)
            assert.is_nil(v)
            assert.is_equal("y", fs.read(p))
        end)
    end)

    describe("sync variants", function ()
        it("work without prompting", function ()
            local p = base / "sync.txt"
            fs.write_sync(p, "s")
            assert.is_equal("s", fs.read_sync(p))
            fs.remove_sync(p)
        end)
    end)
end)
