---@meta luastd.process

--- Process spawning, checked against the host's `run` permission.
---
--- The plain functions are async: when the host has not decided yet they wait
--- raises `PermissionDenied`. Errors are raised as `luastd.Error` tables
--- (kind `ProcessError`).
---@class luastd.process
local process = {}

--- Result returned by `process.run`.
---@class luastd.process.Result
---@field code   integer exit code
---@field stdout string
---@field stderr string

--- A running/completed process handle returned by `process.spawn`.
---@class luastd.process.ProcessHandle
---@field lines fun(self): fun(): string? iterator over stdout lines
---@field wait  fun(self): integer        exit code
---@field kill  fun(self)
---@field pid   fun(self): integer?

--- Run a command and collect its output.
---@async
---@param cmd  string
---@param args string[]?
---@param opts { cwd?: string | luastd.path.Path, env?: table<string, string>, stdin?: string }?
---@return luastd.process.Result
function process.run(cmd, args, opts) end

--- Like `process.run`, but returns `true, result` or `false, error`.
---@async
---@param cmd  string
---@param args string[]?
---@param opts { cwd?: string | luastd.path.Path, env?: table<string, string>, stdin?: string }?
---@return boolean ok
---@return luastd.process.Result | luastd.Error
function process.try_run(cmd, args, opts) end

--- Spawn a command, returning a handle whose `lines()` iterates stdout.
---@async
---@param cmd  string
---@param args string[]?
---@param opts { cwd?: string | luastd.path.Path, env?: table<string, string>, stdin?: string }?
---@return luastd.process.ProcessHandle
function process.spawn(cmd, args, opts) end

return process
