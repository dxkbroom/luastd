---@diagnostic disable: undefined-global
-- Module navigation for this checkout, loaded by `.lazy.lua` as
-- `require("luastd_dev.project")` with the checkout root.
--
-- A module is its `---@meta` stub, `crates/<crate>/definitions/luastd/<m>.lua`
-- (`init.lua` is the root module `luastd`), plus its Rust implementation and
-- its busted spec, found by name:
--
-- - implementation: `crates/<crate>/src/<m>.rs`, `<m>s.rs`, `<m>/mod.rs`, then
--   `<m>.lua` (a Lua half); `lib.rs` for the root module; `EXTRA_IMPL` adds
--   files whose names do not follow the module (async's core is `scheduler.rs`)
-- - spec: `luastd_<m>_spec.lua` (`luastd_spec.lua` for the root), in `spec/`
--   or `crates/<crate>/tests/lua/`
--
-- A file that does not exist yet gets the canonical path, so it can be created.

local root = assert(..., "luastd_dev.project needs the checkout root")

local M = { root = root }

M.ROLES = { "impl", "def", "spec" }
M.ROLE_LABEL = { impl = "implementation", def = "definition", spec = "spec" }

-- Implementation files that do not follow the module name, first.
local EXTRA_IMPL = { async = { "scheduler.rs" } }

local function exists(path)
    return vim.uv.fs_stat(path) ~= nil
end

local function file(role, path)
    return { role = role, path = path, exists = exists(path) }
end

local function first_existing(paths)
    for _, path in ipairs(paths) do
        if exists(path) then
            return path
        end
    end
end

---@param crate_dir string
---@param name      string
local function impl_files(crate_dir, name)
    local src = crate_dir .. "/src/"
    local found = {}
    for _, extra in ipairs(EXTRA_IMPL[name] or {}) do
        if exists(src .. extra) then
            found[#found + 1] = file("impl", src .. extra)
        end
    end
    local candidates = name == "luastd" and { "lib.rs" } or { name .. ".rs", name .. "s.rs", name .. "/mod.rs" }
    local rust = first_existing(vim.tbl_map(function (c) return src .. c end, candidates))
    if rust then
        found[#found + 1] = file("impl", rust)
    end
    if name ~= "luastd" and exists(src .. name .. ".lua") then
        found[#found + 1] = file("impl", src .. name .. ".lua")
    end
    if #found == 0 then
        found[1] = file("impl", src .. candidates[1])
    end
    return found
end

---@param crate_dir string
---@param name      string
local function spec_file(crate_dir, name)
    local canonical = name == "luastd" and "luastd_spec.lua" or ("luastd_" .. name .. "_spec.lua")
    local dirs = { crate_dir .. "/tests/lua/", root .. "/spec/" }
    for _, dir in ipairs(dirs) do
        if exists(dir .. canonical) then
            return file("spec", dir .. canonical)
        end
    end
    -- new specs go next to the crate's runtime specs, else into the busted `spec/`
    local dir = vim.fn.isdirectory(dirs[1]) == 1 and dirs[1] or dirs[2]
    return file("spec", dir .. canonical)
end

--- Every module, root `luastd` first, then by name.
---@return { name: string, crate: string, files: table[] }[]
function M.modules()
    local modules = {}
    for _, def in ipairs(vim.fn.glob(root .. "/crates/*/definitions/luastd/*.lua", false, true)) do
        local crate_dir = def:match("^(.*)/definitions/luastd/[^/]+$")
        local base = vim.fn.fnamemodify(def, ":t:r")
        local name = base == "init" and "luastd" or base
        local files = impl_files(crate_dir, name)
        files[#files + 1] = file("def", def)
        files[#files + 1] = spec_file(crate_dir, name)
        modules[#modules + 1] = { name = name, crate = vim.fn.fnamemodify(crate_dir, ":t"), files = files }
    end
    table.sort(modules, function (a, b)
        if (a.name == "luastd") ~= (b.name == "luastd") then
            return a.name == "luastd"
        end
        return a.name < b.name
    end)
    return modules
end

---@param name string
function M.module(name)
    for _, module in ipairs(M.modules()) do
        if module.name == name then
            return module
        end
    end
end

---@param module table
---@param role   string
---@return table[]
function M.files(module, role)
    return vim.tbl_filter(function (f) return f.role == role end, module.files)
end

--- The module and file role of `path`, if it is one of a module's files.
---@param path string
---@return table? module, string? role
function M.locate(path)
    path = vim.fs.normalize(path)
    for _, module in ipairs(M.modules()) do
        for _, f in ipairs(module.files) do
            if f.path == path then
                return module, f.role
            end
        end
    end
end

function M.relative(path)
    return vim.fs.relpath and vim.fs.relpath(root, path) or path:sub(#root + 2)
end

--- Call `fn(module)` with the current buffer's module, or one picked from a list.
---@param fn    fun(module: table)
---@param title string?
function M.with_module(fn, title)
    local module = M.locate(vim.api.nvim_buf_get_name(0))
    if module then
        return fn(module)
    end
    M.pick(fn, title)
end

local function present(module)
    local n = 0
    for _, f in ipairs(module.files) do
        n = n + (f.exists and 1 or 0)
    end
    return n
end

--- Markdown preview: the module's files with their status, then the head of
--- its definition stub.
---@param module table
local function preview_text(module)
    local lines = { ("# %s  (%s, %d/%d)"):format(module.name, module.crate, present(module), #module.files), "" }
    for _, f in ipairs(module.files) do
        lines[#lines + 1] = ("- [%s] %-14s `%s`%s"):format(
            f.exists and "x" or " ", M.ROLE_LABEL[f.role], M.relative(f.path), f.exists and "" or " (missing)"
        )
    end
    local def = M.files(module, "def")[1]
    if def and def.exists then
        local head = vim.fn.readfile(def.path, "", 40)
        vim.list_extend(lines, { "", "```lua" })
        vim.list_extend(lines, head)
        lines[#lines + 1] = "```"
    end
    return table.concat(lines, "\n")
end

--- Pick a module and call `fn` with it: a snacks.nvim picker with a preview
--- of the module's files when snacks is installed, else `vim.ui.select`.
---@param fn    fun(module: table)
---@param title string?
function M.pick(fn, title)
    title = title or "luastd modules"
    local modules = M.modules()
    local ok, snacks = pcall(require, "snacks")
    if ok and type(snacks) == "table" and snacks.picker then
        local items = {}
        for i, module in ipairs(modules) do
            items[i] = {
                idx = i,
                text = module.name .. " " .. module.crate,
                module = module,
                preview = { text = preview_text(module), ft = "markdown", loc = false }
            }
        end
        return snacks.picker.pick({
            source = "luastd_modules",
            title = title,
            items = items,
            preview = "preview",
            format = function (item)
                local module = item.module
                local n = present(module)
                return {
                    { ("%-10s"):format(module.name), "SnacksPickerLabel" },
                    { ("%-16s"):format(module.crate), "SnacksPickerComment" },
                    { ("%d/%d"):format(n, #module.files),
                        n == #module.files and "SnacksPickerComment" or "DiagnosticWarn" }
                }
            end,
            confirm = function (picker, item)
                picker:close()
                if item then
                    vim.schedule(function () fn(item.module) end)
                end
            end
        })
    end
    vim.ui.select(
        modules,
        {
            prompt = title,
            format_item = function (module)
                return ("%-8s %s"):format(module.name, module.crate)
            end
        },
        function (module)
            if module then
                fn(module)
            end
        end
    )
end

---@param f   table
---@param cmd string? `edit` (default), `split`, ...
function M.open(f, cmd)
    vim.cmd((cmd or "edit") .. " " .. vim.fn.fnameescape(f.path))
    if not f.exists then
        vim.notify("luastd: new file " .. M.relative(f.path) .. " (not written yet)", vim.log.levels.INFO)
    end
end

--- Jump to the module's `role` file. From one implementation file, `impl`
--- moves on to the next one (async: scheduler.rs, async.lua).
---@param role string
function M.jump(role)
    local current = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
    M.with_module(function (module)
        local files = M.files(module, role)
        local target = files[1]
        for i, f in ipairs(files) do
            if f.path == current then
                target = files[i % #files + 1]
            end
        end
        M.open(target)
    end, "luastd: go to " .. M.ROLE_LABEL[role])
end

--- A new tab with the module's implementation, definition and spec stacked
--- top to bottom.
---@param module table
function M.layout(module)
    local order = { M.files(module, "impl")[1], M.files(module, "def")[1], M.files(module, "spec")[1] }
    for i, f in ipairs(order) do
        vim.cmd((i == 1 and "tabnew" or "belowright split") .. " " .. vim.fn.fnameescape(f.path))
    end
    vim.cmd("wincmd =")
    vim.cmd("1wincmd w")
end

--- Create a missing module file (and its directory) after asking.
---@param f       table
---@param on_done fun()?
function M.create(f, on_done)
    vim.ui.select(
        { "Create", "Cancel" },
        {
            prompt = "luastd: create " .. M.relative(f.path) .. "?"
        },
        function (choice)
            if choice ~= "Create" then
                return
            end
            vim.fn.mkdir(vim.fs.dirname(f.path), "p")
            vim.fn.writefile({}, f.path)
            f.exists = true
            if on_done then
                on_done()
            end
        end
    )
end

--- The kotlinx.coroutines checkout the Kotlin test ports point at:
--- `vim.g.luastd_kotlinx_dir`, else `$KOTLINX_DIR`, else `../kotlinx.coroutines`
--- next to this checkout.
---@return string
function M.kotlinx_dir()
    return vim.fs.normalize(vim.g.luastd_kotlinx_dir or vim.env.KOTLINX_DIR or (root .. "/../kotlinx.coroutines"))
end

--- In a Kotlin test port (`tests/lua/kotlinx/<Class>.lua`): the `-- kotlin:`
--- reference above the cursor and the `it`/`pending` name around it.
---@return { path: string, tag: string, class: string?, test: string? }?
local function kotlin_target()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local test, class
    for i = row, 1, -1 do
        local line = lines[i]
        if not test then
            test = line:match('^%s*it%(%s*"([^"]+)"') or line:match('^%s*pending%(%s*"([^"]+)"')
            if not test and (line:match("^%s*it%(%s*$") or line:match("^%s*pending%(%s*$")) and lines[i + 1] then
                test = lines[i + 1]:match('^%s*"([^"]+)"')
            end
        end
        class = class or line:match('^%s*describe%(%s*"([^"]+)"')
        local path, tag = line:match("^%s*%-%- kotlin:%s*(%S+)@(%S+)%s*$")
        if path then
            return { path = path, tag = tag, class = class, test = test }
        end
    end
    -- the cursor is above the first describe: use the first reference
    for i, line in ipairs(lines) do
        local path, tag = line:match("^%s*%-%- kotlin:%s*(%S+)@(%S+)%s*$")
        if path then
            return { path = path, tag = tag, class = (lines[i + 1] or ""):match('^%s*describe%(%s*"([^"]+)"') }
        end
    end
end

--- Jump from a Kotlin test port to the Kotlin source: the `fun` of the
--- `it`/`pending` under the cursor, else the class. Reads
--- `<kotlinx>/.git/cdtag/<tag>/<path>`, falling back to `git show <tag>:<path>`
--- in a scratch buffer.
function M.kotlin()
    local target = kotlin_target()
    if not target then
        vim.notify("luastd: no `-- kotlin: <path>@<tag>` line here (not a Kotlin test port)", vim.log.levels.WARN)
        return
    end
    local dir = M.kotlinx_dir()
    if vim.fn.isdirectory(dir) == 0 then
        vim.notify(
            ("luastd: kotlinx.coroutines checkout not found at %s (set vim.g.luastd_kotlinx_dir or $KOTLINX_DIR)")
                :format(dir),
            vim.log.levels.WARN
        )
        return
    end
    local file = ("%s/.git/cdtag/%s/%s"):format(dir, target.tag, target.path)
    if exists(file) then
        vim.cmd("edit " .. vim.fn.fnameescape(file))
    else
        local out = vim.fn.systemlist({ "git", "-C", dir, "show", target.tag .. ":" .. target.path })
        if vim.v.shell_error ~= 0 then
            vim.notify(("luastd: %s@%s not found in %s"):format(target.path, target.tag, dir), vim.log.levels.WARN)
            return
        end
        local name = ("kotlinx://%s/%s"):format(target.tag, target.path)
        local buf = vim.fn.bufnr(name)
        if buf == -1 then
            buf = vim.api.nvim_create_buf(true, true)
            vim.api.nvim_buf_set_name(buf, name)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
            vim.bo[buf].modifiable = false
            vim.bo[buf].filetype = "kotlin"
        end
        vim.api.nvim_set_current_buf(buf)
    end
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local found = target.test and vim.fn.search("\\<fun\\s\\+" .. target.test .. "\\>", "cW") > 0
    if not found and target.class then
        found = vim.fn.search("\\<class\\s\\+" .. target.class .. "\\>", "cW") > 0
    end
    if found then
        vim.cmd("normal! zz")
    elseif target.test then
        vim.notify(("luastd: no fun %s in %s"):format(target.test, target.path), vim.log.levels.WARN)
    end
end

--- Open the Neo-tree source backed by `kotlin:report --json`.
function M.test_tree()
    local ok, command = pcall(require, "neo-tree.command")
    if not ok then
        vim.notify("luastd: neo-tree unavailable\n" .. tostring(command), vim.log.levels.WARN)
        return
    end
    command.execute({ source = "luastd_tests", position = "current" })
end

local test_winbar_values = {}

local function test_case_name(lines, index)
    local line = lines[index]
    local name = line:match('^%s*it%(%s*"([^"]+)"') or line:match('^%s*pending%(%s*"([^"]+)"')
    if not name and (line:match("^%s*it%(%s*$") or line:match("^%s*pending%(%s*$")) then
        name = (lines[index + 1] or ""):match('^%s*"([^"]+)"')
    end
    return name
end

local function update_test_winbar()
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    local path = vim.api.nvim_buf_get_name(buf)
    local header
    if path:find("/tests/lua/kotlinx/", 1, true) then
        local row = vim.api.nvim_win_get_cursor(win)[1]
        local lines = vim.api.nvim_buf_get_lines(buf, 0, row, false)
        local class, test
        for index, line in ipairs(lines) do
            class = line:match('^%s*describe%(%s*"([^"]+)"') or class
            test = test_case_name(lines, index) or test
        end
        if class and test then
            header = class .. "  ›  " .. test
        end
    end

    local previous = test_winbar_values[win]
    if header then
        local value = " " .. header
        if value ~= previous then
            vim.wo[win].winbar = value
            test_winbar_values[win] = value
        end
    elseif previous then
        vim.wo[win].winbar = ""
        test_winbar_values[win] = nil
    end
end

local function explorer()
    local ok, command = pcall(require, "neo-tree.command")
    if not ok then
        vim.notify("luastd: neo-tree unavailable, picking a module instead\n" .. tostring(command), vim.log.levels.INFO)
        return M.pick(M.layout, "luastd: open module")
    end
    local name = vim.api.nvim_buf_get_name(0)
    command.execute({
        source = "luastd",
        position = "current",
        reveal_file = M.locate(name) and name or nil
    })
end

function M.keymaps()
    local map = function (lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, { desc = desc })
    end
    map("<leader>pe", explorer, "[E]xplorer (modules)")
    map("<leader>pgi", function () M.jump("impl") end, "[I]mplementation")
    map("<leader>pgd", function () M.jump("def") end, "[D]efinition")
    map("<leader>pgs", function () M.jump("spec") end, "[S]pec")
    map("<leader>pgk", M.kotlin, "[K]otlin test (from a kotlinx/ port)")
    map("<leader>pt", M.test_tree, "[T]est cases (workspace tree)")
    map("<leader>pv", function () M.with_module(M.layout, "luastd: open module") end, "[V]iew module (impl, def, spec)")
    map("<leader>pm", function () M.pick(M.layout, "luastd: open module") end, "pick [M]odule")
    local ok, wk = pcall(require, "which-key")
    if ok and wk.add then
        wk.add({
            { "<leader>p", group = "[P]roject" },
            { "<leader>pg", group = "[G]o to" }
        })
    end
    local group = vim.api.nvim_create_augroup("luastd_test_sticky_header", { clear = true })
    vim.api.nvim_create_autocmd({ "BufEnter", "CursorMoved", "WinEnter", "TextChanged", "InsertLeave" }, {
        group = group,
        callback = update_test_winbar
    })
    update_test_winbar()
end

return M
