---@diagnostic disable: undefined-global
-- Neo-tree source for Kotlin coroutine Lua ports, backed by kotlin:report.

local project = require("luastd_dev.project")
local manager = require("neo-tree.sources.manager")
local renderer = require("neo-tree.ui.renderer")
local highlights = require("neo-tree.ui.highlights")
local cc = require("neo-tree.sources.common.commands")
local common_components = require("neo-tree.sources.common.components")
local utils = require("neo-tree.utils")

local NAME = "luastd_tests"
local M = { name = NAME, display_name = " 󰙨 Kotlin tests " }

local function class_id(name)
    return "luastd-test-class:" .. name
end

local function report_nodes()
    local result = vim
        .system({ "mise", "run", "--quiet", "kotlin:report", "--json" }, { cwd = project.root, text = true })
        :wait()
    if result.code ~= 0 then
        error("kotlin:report failed: " .. (result.stderr or result.stdout))
    end
    local ok, report = pcall(vim.json.decode, result.stdout)
    if not ok or type(report) ~= "table" then
        error("could not decode kotlin:report JSON")
    end

    local nodes = {}
    for _, cls in ipairs(report.classes or {}) do
        if cls.lua_port then
            local path = project.root .. "/" .. cls.lua_port
            local children = {}
            for _, test in ipairs(cls.tests or {}) do
                children[#children + 1] = {
                    id = ("luastd-test:%s:%s"):format(cls.name, test.name),
                    name = test.name,
                    path = path,
                    type = "file",
                    extra = {
                        status = test.status,
                        line = test.lua_line,
                        position = test.lua_line and { test.lua_line - 1, 0 } or nil
                    }
                }
            end
            nodes[#nodes + 1] = {
                id = class_id(cls.name),
                name = cls.name,
                path = path,
                type = "directory",
                loaded = true,
                children = children,
                extra = { source = cls.kotlin_source, lua_port = cls.lua_port, counts = cls.counts }
            }
        end
    end
    return nodes
end

function M.navigate(state, path, path_to_reveal, callback)
    state.path = project.root
    local ok, nodes = pcall(report_nodes)
    if not ok then
        vim.notify("luastd: " .. tostring(nodes), vim.log.levels.ERROR)
        nodes = {}
    end

    local expand = {}
    if not state.luastd_tests_expanded_once then
        state.luastd_tests_expanded_once = true
        local current = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
        for _, node in ipairs(nodes) do
            if vim.fs.normalize(node.path) == current then
                expand[#expand + 1] = node.id
            end
        end
    end
    if path_to_reveal then
        for _, node in ipairs(nodes) do
            if vim.fs.normalize(node.path) == vim.fs.normalize(path_to_reveal) then
                expand[#expand + 1] = node.id
            end
        end
    end

    state.default_expanded_nodes = expand
    renderer.show_nodes(nodes, state)
    state.default_expanded_nodes = nil
    if callback then
        vim.schedule(callback)
    end
end

function M.setup(config, global_config) end

local components = vim.tbl_extend("force", {}, common_components)

components.test_tree_name = function (config, node, state)
    local highlight = node.type == "directory" and highlights.DIRECTORY_NAME or highlights.FILE_NAME
    return { text = node.name, highlight = highlight }
end

components.test_tree_info = function (config, node, state)
    local extra = node.extra or {}
    if node.type == "directory" then
        local counts = extra.counts or {}
        return {
            text = ("  %s  %d cases"):format(
                extra.lua_port or "",
                (counts.ported or 0) + (counts.adapted or 0)
                    + (counts.not_applicable or 0) + (counts.defer or 0)
                    + (counts.todo or 0) + (counts.missing or 0)
            ),
            highlight = highlights.DIM_TEXT
        }
    end
    local location = extra.line and ("line " .. extra.line) or "no Lua line"
    return { text = ("  %s · %s"):format(extra.status or "unknown", location), highlight = highlights.DIM_TEXT }
end

M.components = components

local commands = {}
local refresh = utils.wrap(manager.refresh, NAME)
commands.refresh = refresh
commands.open = function (state) cc.open(state) end
commands.open_split = function (state) cc.open_split(state) end
commands.open_vsplit = function (state) cc.open_vsplit(state) end
commands.open_tabnew = function (state) cc.open_tabnew(state) end
cc._add_common_commands(commands)
M.commands = commands

M.default_config = {
    renderers = {
        directory = {
            { "indent" },
            { "icon" },
            { "test_tree_name" },
            { "test_tree_info" }
        },
        file = {
            { "indent" },
            { "icon" },
            { "test_tree_name" },
            { "test_tree_info" }
        }
    },
    window = {
        mappings = { ["R"] = "refresh" }
    }
}

return M
