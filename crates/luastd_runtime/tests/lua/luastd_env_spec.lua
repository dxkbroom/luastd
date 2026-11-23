-- The harness runs every `it` body inside the spec's coroutine, so they may
-- call `---@async` functions.
---@diagnostic disable: await-in-sync

local env = require("luastd.env")

---@param fn fun()
---@return luastd.Error
local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return err --[[@as luastd.Error]]
end

describe("luastd.env", function ()
    describe("get", function ()
        it("reads an allowed variable", function ()
            assert.is_equal(type(env.get("PATH")), "string")
            assert.is_true(env.has("PATH"))
        end)

        it("returns nil for an allowed but unset variable", function ()
            assert.is_nil(env.get("LUASTD_SPEC"))
            assert.is_false(env.has("LUASTD_SPEC"))
        end)

        it("raises PermissionDenied for a denied variable", function ()
            local err = error_of(function () env.get("LUASTD_SPEC_DENIED") end) --[[@as luastd.PermissionDeniedError]]
            assert.is_equal("PermissionDenied", err.kind)
            assert.is_equal("env", err.permission)
            assert.is_equal("LUASTD_SPEC_DENIED", err.target)
            assert.matches("^PermissionDenied: ", tostring(err))
        end)

        it("asks the host and remembers a grant", function ()
            assert.is_not_nil(env.get("HOME"))
            assert.is_not_nil(env.get("HOME"))
        end)

        it("asks the host and remembers a denial", function ()
            assert.is_equal("PermissionDenied", error_of(function () env.get("USER") end).kind)
            assert.is_equal("PermissionDenied", error_of(function () env.get("USER") end).kind)
        end)

        it("rejects bad names", function ()
            local err = error_of(function ()
                ---@diagnostic disable-next-line: param-type-mismatch
                env.get(42)
            end)
            assert.is_equal("InvalidArgument", err.kind)
            assert.is_equal("InvalidArgument", error_of(function () env.get("A=B") end).kind)
        end)
    end)

    describe("set and unset", function ()
        it("change only the overlay", function ()
            env.set("LUASTD_SPEC", "on")
            assert.is_equal("on", env.get("LUASTD_SPEC"))
            env.unset("LUASTD_SPEC")
            assert.is_nil(env.get("LUASTD_SPEC"))
        end)

        it("unset hides a process variable", function ()
            env.unset("PATH")
            assert.is_false(env.has("PATH"))
        end)
    end)

    describe("vars", function ()
        it("needs access to every variable", function ()
            local err = error_of(function () env.vars() end) --[[@as luastd.PermissionDeniedError]]
            assert.is_equal("PermissionDenied", err.kind)
            assert.is_nil(err.target)
        end)
    end)
end)
