//! The `luastd.fs` effect module (cargo feature `fs`).
//!
//! Filesystem access through permission checks. Every function is
//! `---@async`: when the host has not decided yet it awaits the host's
//! [`Prompter`](crate::Prompter). `try_*` variants return `true, value` on
//! success or `false, err` on failure and never catch cancellation.

use std::path::PathBuf;
use std::time::UNIX_EPOCH;

use deno_permissions::{OpenAccessKind, PermissionState, PermissionsContainer};
use mlua::{Lua, MultiValue, Table, Value};

use crate::EffectModule;
use crate::errors::LuaError;
use crate::prompt::{Descriptor, check};

use luastd::path::PathLua;

/// The `luastd.fs` module.
pub struct Fs;

pub(crate) struct FsReadDescriptor(pub PathBuf);
pub(crate) struct FsWriteDescriptor(pub PathBuf);

impl Descriptor for FsReadDescriptor {
    const PERMISSION: &'static str = "read";

    fn target(&self) -> Option<String> {
        Some(self.0.to_string_lossy().to_string())
    }

    fn query(&self, container: &PermissionsContainer) -> PermissionState {
        container
            .query_read(Some(&self.0.to_string_lossy()))
            .unwrap_or(PermissionState::Denied)
    }

    fn request(&self, container: &PermissionsContainer) -> PermissionState {
        container
            .request_read(Some(&self.0.to_string_lossy()))
            .unwrap_or(PermissionState::Denied)
    }

    fn check(&self, container: &PermissionsContainer) -> Result<(), String> {
        container
            .check_open(
                std::borrow::Cow::Borrowed(&self.0),
                OpenAccessKind::Read,
                Some("luastd.fs"),
            )
            .map_err(|error| error.to_string())?;
        Ok(())
    }
}

impl Descriptor for FsWriteDescriptor {
    const PERMISSION: &'static str = "write";

    fn target(&self) -> Option<String> {
        Some(self.0.to_string_lossy().to_string())
    }

    fn query(&self, container: &PermissionsContainer) -> PermissionState {
        container
            .query_write(Some(&self.0.to_string_lossy()))
            .unwrap_or(PermissionState::Denied)
    }

    fn request(&self, container: &PermissionsContainer) -> PermissionState {
        container
            .request_write(Some(&self.0.to_string_lossy()))
            .unwrap_or(PermissionState::Denied)
    }

    fn check(&self, container: &PermissionsContainer) -> Result<(), String> {
        container
            .check_open(
                std::borrow::Cow::Borrowed(&self.0),
                OpenAccessKind::Write,
                Some("luastd.fs"),
            )
            .map_err(|error| error.to_string())?;
        Ok(())
    }
}

impl EffectModule for Fs {
    const NAME: &'static str = "luastd.fs";

    fn create(lua: &Lua, permissions: &PermissionsContainer) -> mlua::Result<Table> {
        let module = lua.create_table()?;

        // read
        {
            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move { read_async(&lua, &perms, &args).await }
            })?;
            module.set("read", f)?;

            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move { try_read_async(&lua, &perms, &args).await }
            })?;
            module.set("try_read", f)?;
        }

        // write
        {
            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move { write_async(&lua, &perms, &args).await }
            })?;
            module.set("write", f)?;

            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move { try_write_async(&lua, &perms, &args).await }
            })?;
            module.set("try_write", f)?;
        }

        // list
        {
            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move { list_async(&lua, &perms, &args).await }
            })?;
            module.set("list", f)?;

            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move { try_list_async(&lua, &perms, &args).await }
            })?;
            module.set("try_list", f)?;
        }

        // stat
        {
            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move { stat_async(&lua, &perms, &args).await }
            })?;
            module.set("stat", f)?;

            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move { try_stat_async(&lua, &perms, &args).await }
            })?;
            module.set("try_stat", f)?;
        }

        // mkdir
        {
            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move { mkdir_async(&lua, &perms, &args).await }
            })?;
            module.set("mkdir", f)?;

            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move { try_mkdir_async(&lua, &perms, &args).await }
            })?;
            module.set("try_mkdir", f)?;
        }

        // remove
        {
            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move { remove_async(&lua, &perms, &args).await }
            })?;
            module.set("remove", f)?;

            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move { try_remove_async(&lua, &perms, &args).await }
            })?;
            module.set("try_remove", f)?;
        }

        // rename
        {
            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move { rename_async(&lua, &perms, &args).await }
            })?;
            module.set("rename", f)?;

            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move { try_rename_async(&lua, &perms, &args).await }
            })?;
            module.set("try_rename", f)?;
        }

        Ok(module)
    }
}

// ---------- argument helpers ----------

fn bad_argument(index: usize, name: &str, function: &str, expected: &str) -> LuaError {
    LuaError::new(
        "InvalidArgument",
        format!("bad argument #{index} '{name}' to '{function}' ({expected})"),
    )
}

fn path_arg(args: &MultiValue, index: usize, function: &str) -> Result<PathBuf, LuaError> {
    match args.get(index - 1) {
        Some(Value::String(text)) => {
            let s = text
                .to_str()
                .map_err(|_| bad_argument(index, "path", function, "UTF-8 string expected"))?;
            if s.is_empty() {
                return Err(bad_argument(
                    index,
                    "path",
                    function,
                    "non-empty string expected",
                ));
            }
            Ok(PathBuf::from(s.to_owned()))
        }
        // Accept `luastd.path.Path` (and any userdata that stringifies to a path).
        Some(Value::UserData(_)) => {
            let value = args.get(index - 1).unwrap();
            let s = value
                .to_string()
                .map_err(|_| bad_argument(index, "path", function, "path expected"))?;
            if s.is_empty() {
                return Err(bad_argument(
                    index,
                    "path",
                    function,
                    "non-empty path expected",
                ));
            }
            Ok(PathBuf::from(s))
        }
        _ => Err(bad_argument(
            index,
            "path",
            function,
            "string or luastd.path.Path expected",
        )),
    }
}

fn string_arg(args: &MultiValue, index: usize, function: &str) -> Result<Vec<u8>, LuaError> {
    match args.get(index - 1) {
        Some(Value::String(text)) => Ok(text.as_bytes().to_vec()),
        _ => Err(bad_argument(index, "contents", function, "string expected")),
    }
}

fn fs_error(op: &str, path: &std::path::Path, error: std::io::Error) -> LuaError {
    LuaError::new("FsError", format!("{op}: {error}"))
        .with("path", path.to_string_lossy().to_string())
}

fn ok_value(value: Value) -> MultiValue {
    let mut mv = MultiValue::new();
    mv.push_back(Value::Boolean(true));
    mv.push_back(value);
    mv
}

fn err_value(lua: &Lua, err: mlua::Error) -> mlua::Result<MultiValue> {
    let table = match LuaError::find(&err) {
        Some(le) => le.table(lua)?,
        None => LuaError::new("FsError", err.to_string()).table(lua)?,
    };
    let mut mv = MultiValue::new();
    mv.push_back(Value::Boolean(false));
    mv.push_back(Value::Table(table));
    Ok(mv)
}

// ---------- read ----------

async fn read_async(
    lua: &Lua,
    perms: &PermissionsContainer,
    args: &MultiValue,
) -> mlua::Result<Value> {
    let path = path_arg(args, 1, "read")?;
    check(lua, perms, FsReadDescriptor(path.clone())).await?;
    let bytes = tokio::fs::read(&path)
        .await
        .map_err(|e| fs_error("read", &path, e))?;
    Ok(Value::String(lua.create_string(&bytes)?))
}

async fn try_read_async(
    lua: &Lua,
    perms: &PermissionsContainer,
    args: &MultiValue,
) -> Result<MultiValue, mlua::Error> {
    match read_async(lua, perms, args).await {
        Ok(v) => Ok(ok_value(v)),
        Err(e) => {
            if let Some(le) = LuaError::find(&e)
                && le.kind() == "Cancelled"
            {
                return Err(e);
            }
            err_value(lua, e)
        }
    }
}

// ---------- write ----------

async fn write_async(
    lua: &Lua,
    perms: &PermissionsContainer,
    args: &MultiValue,
) -> mlua::Result<Value> {
    let path = path_arg(args, 1, "write")?;
    let contents = string_arg(args, 2, "write")?;
    check(lua, perms, FsWriteDescriptor(path.clone())).await?;
    tokio::fs::write(&path, contents)
        .await
        .map_err(|e| fs_error("write", &path, e))?;
    Ok(Value::Nil)
}

async fn try_write_async(
    lua: &Lua,
    perms: &PermissionsContainer,
    args: &MultiValue,
) -> Result<MultiValue, mlua::Error> {
    match write_async(lua, perms, args).await {
        Ok(v) => Ok(ok_value(v)),
        Err(e) => {
            if let Some(le) = LuaError::find(&e)
                && le.kind() == "Cancelled"
            {
                return Err(e);
            }
            err_value(lua, e)
        }
    }
}

// ---------- list ----------

async fn list_async(
    lua: &Lua,
    perms: &PermissionsContainer,
    args: &MultiValue,
) -> mlua::Result<Value> {
    let path = path_arg(args, 1, "list")?;
    check(lua, perms, FsReadDescriptor(path.clone())).await?;
    let mut rd = tokio::fs::read_dir(&path)
        .await
        .map_err(|e| fs_error("list", &path, e))?;
    let mut names = Vec::new();
    while let Some(entry) = rd
        .next_entry()
        .await
        .map_err(|e| fs_error("list", &path, e))?
    {
        names.push(entry.file_name().to_string_lossy().to_string());
    }
    names.sort();
    let table = lua.create_table()?;
    for (i, name) in (1..).zip(names) {
        let full = path.join(name).to_string_lossy().to_string();
        table.set(i, lua.create_userdata(PathLua::new(full))?)?;
    }
    Ok(Value::Table(table))
}

async fn try_list_async(
    lua: &Lua,
    perms: &PermissionsContainer,
    args: &MultiValue,
) -> Result<MultiValue, mlua::Error> {
    match list_async(lua, perms, args).await {
        Ok(v) => Ok(ok_value(v)),
        Err(e) => {
            if let Some(le) = LuaError::find(&e)
                && le.kind() == "Cancelled"
            {
                return Err(e);
            }
            err_value(lua, e)
        }
    }
}

// ---------- stat ----------

fn stat_table(
    lua: &Lua,
    path: &PathBuf,
    meta: std::fs::Metadata,
    symlink: bool,
) -> mlua::Result<Table> {
    let table = lua.create_table()?;
    let size = meta.len();
    let is_dir = meta.is_dir();
    let is_file = meta.is_file();
    table.set("size", size)?;
    table.set("is_file", is_file)?;
    table.set("is_dir", is_dir)?;
    table.set("is_symlink", symlink)?;
    table.set("isFile", is_file)?;
    table.set("isDirectory", is_dir)?;
    table.set("isSymlink", symlink)?;
    let kind = if symlink {
        "symlink"
    } else if is_dir {
        "directory"
    } else if is_file {
        "file"
    } else {
        "other"
    };
    table.set("type", kind)?;
    table.set("readonly", meta.permissions().readonly())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        table.set("mode", meta.permissions().mode())?;
    }
    if let Ok(t) = meta.modified()
        && let Ok(d) = t.duration_since(UNIX_EPOCH)
    {
        table.set("modified", d.as_secs() as i64)?;
        table.set("mtime", d.as_secs() as i64)?;
    }
    if let Ok(t) = meta.accessed()
        && let Ok(d) = t.duration_since(UNIX_EPOCH)
    {
        table.set("accessed", d.as_secs() as i64)?;
        table.set("atime", d.as_secs() as i64)?;
    }
    if let Ok(t) = meta.created()
        && let Ok(d) = t.duration_since(UNIX_EPOCH)
    {
        table.set("created", d.as_secs() as i64)?;
        table.set("birthtime", d.as_secs() as i64)?;
        table.set("ctime", d.as_secs() as i64)?;
    }
    let _ = path;
    Ok(table)
}

async fn stat_async(
    lua: &Lua,
    perms: &PermissionsContainer,
    args: &MultiValue,
) -> mlua::Result<Value> {
    let path = path_arg(args, 1, "stat")?;
    check(lua, perms, FsReadDescriptor(path.clone())).await?;
    let meta = tokio::fs::metadata(&path)
        .await
        .map_err(|e| fs_error("stat", &path, e))?;
    let sym_meta = tokio::fs::symlink_metadata(&path).await.ok();
    let symlink = sym_meta
        .map(|m| m.file_type().is_symlink())
        .unwrap_or(false);
    let table = stat_table(lua, &path, meta, symlink)?;
    Ok(Value::Table(table))
}

async fn try_stat_async(
    lua: &Lua,
    perms: &PermissionsContainer,
    args: &MultiValue,
) -> Result<MultiValue, mlua::Error> {
    match stat_async(lua, perms, args).await {
        Ok(v) => Ok(ok_value(v)),
        Err(e) => {
            if let Some(le) = LuaError::find(&e)
                && le.kind() == "Cancelled"
            {
                return Err(e);
            }
            err_value(lua, e)
        }
    }
}

// ---------- mkdir ----------

async fn mkdir_async(
    lua: &Lua,
    perms: &PermissionsContainer,
    args: &MultiValue,
) -> mlua::Result<Value> {
    let path = path_arg(args, 1, "mkdir")?;
    check(lua, perms, FsWriteDescriptor(path.clone())).await?;
    tokio::fs::create_dir_all(&path)
        .await
        .map_err(|e| fs_error("mkdir", &path, e))?;
    Ok(Value::Nil)
}

async fn try_mkdir_async(
    lua: &Lua,
    perms: &PermissionsContainer,
    args: &MultiValue,
) -> Result<MultiValue, mlua::Error> {
    match mkdir_async(lua, perms, args).await {
        Ok(v) => Ok(ok_value(v)),
        Err(e) => {
            if let Some(le) = LuaError::find(&e)
                && le.kind() == "Cancelled"
            {
                return Err(e);
            }
            err_value(lua, e)
        }
    }
}

// ---------- remove ----------

async fn remove_async(
    lua: &Lua,
    perms: &PermissionsContainer,
    args: &MultiValue,
) -> mlua::Result<Value> {
    let path = path_arg(args, 1, "remove")?;
    check(lua, perms, FsWriteDescriptor(path.clone())).await?;
    let meta = tokio::fs::metadata(&path).await;
    if meta.map(|m| m.is_dir()).unwrap_or(false) {
        tokio::fs::remove_dir_all(&path)
            .await
            .map_err(|e| fs_error("remove", &path, e))?;
    } else {
        tokio::fs::remove_file(&path)
            .await
            .map_err(|e| fs_error("remove", &path, e))?;
    }
    Ok(Value::Nil)
}

async fn try_remove_async(
    lua: &Lua,
    perms: &PermissionsContainer,
    args: &MultiValue,
) -> Result<MultiValue, mlua::Error> {
    match remove_async(lua, perms, args).await {
        Ok(v) => Ok(ok_value(v)),
        Err(e) => {
            if let Some(le) = LuaError::find(&e)
                && le.kind() == "Cancelled"
            {
                return Err(e);
            }
            err_value(lua, e)
        }
    }
}

// ---------- rename ----------

async fn rename_async(
    lua: &Lua,
    perms: &PermissionsContainer,
    args: &MultiValue,
) -> mlua::Result<Value> {
    let from = path_arg(args, 1, "rename")?;
    let to = path_arg(args, 2, "rename")?;
    check(lua, perms, FsWriteDescriptor(from.clone())).await?;
    check(lua, perms, FsWriteDescriptor(to.clone())).await?;
    tokio::fs::rename(&from, &to)
        .await
        .map_err(|e| fs_error("rename", &from, e))?;
    Ok(Value::Nil)
}

async fn try_rename_async(
    lua: &Lua,
    perms: &PermissionsContainer,
    args: &MultiValue,
) -> Result<MultiValue, mlua::Error> {
    match rename_async(lua, perms, args).await {
        Ok(v) => Ok(ok_value(v)),
        Err(e) => {
            if let Some(le) = LuaError::find(&e)
                && le.kind() == "Cancelled"
            {
                return Err(e);
            }
            err_value(lua, e)
        }
    }
}
