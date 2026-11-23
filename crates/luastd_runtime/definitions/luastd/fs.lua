---@meta luastd.fs

--- Filesystem access, checked against the host's `read` and `write` permissions.
---
--- The plain functions are async: when the host has not decided yet they wait
--- for its prompt. The `*_sync` variants never wait; an undecided permission
--- raises `PermissionDenied`. Errors are raised as `luastd.Error` tables
--- (kind `FsError`, with a `path` field for IO errors).
---@class luastd.fs
local fs = {}

--- Metadata returned by `fs.stat`.
---@class luastd.fs.Stat
---@field size        integer                                    file size in bytes
---@field is_file     boolean
---@field is_dir      boolean
---@field is_symlink  boolean
---@field isFile      boolean                                    alias of `is_file`
---@field isDirectory boolean                                    alias of `is_dir`
---@field isSymlink   boolean                                    alias of `is_symlink`
---@field type        "file" | "directory" | "symlink" | "other"
---@field
---@field mode        integer?                                   permission bits (Unix only)
---@field modified    integer?                                   seconds since epoch
---@field mtime       integer?                                   alias of `modified`
---@field accessed    integer?                                   seconds since epoch
---@field atime       integer?                                   alias of `accessed`
---@field created     integer?                                   seconds since epoch
---@field birthtime   integer?                                   alias of `created`
---@field ctime       integer?                                   alias of `created`

--- Read a file's contents.
---@async
---@param path string | luastd.path.Path
---@return string
function fs.read(path) end

--- Write `contents` to a file.
---@async
---@param path     string | luastd.path.Path
---@param contents string
function fs.write(path, contents) end

--- List a directory's entry names.
---@async
---@param path string | luastd.path.Path
---@return luastd.path.Path[]
function fs.list(path) end

--- Stat a path.
---@async
---@param path string | luastd.path.Path
---@return luastd.fs.Stat
function fs.stat(path) end

--- Create a directory (and parents).
---@async
---@param path string | luastd.path.Path
function fs.mkdir(path) end

--- Remove a file or directory.
---@async
---@param path string | luastd.path.Path
function fs.remove(path) end

--- Rename / move a path.
---@async
---@param from string | luastd.path.Path
---@param to   string | luastd.path.Path
function fs.rename(from, to) end

--- `fs.read` without prompting.
---@param path string | luastd.path.Path
---@return string
function fs.read_sync(path) end

--- `fs.write` without prompting.
---@param path     string | luastd.path.Path
---@param contents string
function fs.write_sync(path, contents) end

--- `fs.list` without prompting.
---@param path string | luastd.path.Path
---@return luastd.path.Path[]
function fs.list_sync(path) end

--- `fs.stat` without prompting.
---@param path string | luastd.path.Path
---@return luastd.fs.Stat
function fs.stat_sync(path) end

--- `fs.mkdir` without prompting.
---@param path string | luastd.path.Path
function fs.mkdir_sync(path) end

--- `fs.remove` without prompting.
---@param path string | luastd.path.Path
function fs.remove_sync(path) end

--- `fs.rename` without prompting.
---@param from string | luastd.path.Path
---@param to   string | luastd.path.Path
function fs.rename_sync(from, to) end

--- `try_*` form of `fs.read`: `true` and the contents, or `false` and the
--- error instead of raising it. Cancellation is not caught (ADR 0005).
---@async
---@param path string | luastd.path.Path
---@return_overload true, string
---@return_overload false, luastd.Error
function fs.try_read(path) end

--- `try_*` form of `fs.write`.
---@async
---@param path     string | luastd.path.Path
---@param contents string
---@return_overload true, nil
---@return_overload false, luastd.Error
function fs.try_write(path, contents) end

--- `try_*` form of `fs.list`.
---@async
---@param path string | luastd.path.Path
---@return_overload true, luastd.path.Path[]
---@return_overload false, luastd.Error
function fs.try_list(path) end

--- `try_*` form of `fs.stat`.
---@async
---@param path string | luastd.path.Path
---@return_overload true, luastd.fs.Stat
---@return_overload false, luastd.Error
function fs.try_stat(path) end

--- `try_*` form of `fs.mkdir`.
---@async
---@param path string | luastd.path.Path
---@return_overload true, nil
---@return_overload false, luastd.Error
function fs.try_mkdir(path) end

--- `try_*` form of `fs.remove`.
---@async
---@param path string | luastd.path.Path
---@return_overload true, nil
---@return_overload false, luastd.Error
function fs.try_remove(path) end

--- `try_*` form of `fs.rename`.
---@async
---@param from string | luastd.path.Path
---@param to   string | luastd.path.Path
---@return_overload true, nil
---@return_overload false, luastd.Error
function fs.try_rename(from, to) end

return fs
