-- tinyvi init.lua — demonstrates the Lua plugin API.
local tinyvi = _G.tinyvi

tinyvi.log("tinyvi booted")

-- A custom command: `:hello` prints a greeting into the status line.
tinyvi.command("hello", function()
    tinyvi.log("hello from a Lua plugin")
end)

-- A command that uses the runtime: list the current directory.
tinyvi.command("ls", function()
    local fs = require("luastd.fs")
    local path = require("luastd.path")
    local entries = fs.list(path.new("."))
    tinyvi.log("entries: " .. #entries)
end)