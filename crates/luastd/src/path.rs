//! The `luastd.path` Lua module.
//!
//! Wraps the lexical path operations from the `camino` crate. Construct paths
//! with `path.new`; values are Lua userdata with immutable methods,
//! Python-style `/` joining, `tostring`, and comparison operators. Nothing in
//! this module touches the filesystem: no path is opened, read, canonicalized,
//! or stat-ed.

use std::cmp::Ordering;
use std::fmt;

use camino::{Utf8Component, Utf8PathBuf};
use mlua::prelude::*;
use mlua::{Table, UserData};

use crate::Module;
use crate::util::{bad_argument, string_argument};

/// Raised when an extension argument contains a path separator.
const EXTENSION_SEPARATOR_ERROR: &str =
    "invalid extension: extension cannot contain path separators";

pub const TYPE_NAME: &str = "luastd.path.Path";

/// A UTF-8 path exposed to Lua.
#[derive(Clone, Debug)]
pub struct PathLua(Utf8PathBuf);

impl PathLua {
    /// Construct from a UTF-8 path string. Used by effect modules that
    /// hand paths back to Lua (e.g. `luastd.fs`).
    pub fn new(path: impl AsRef<str>) -> Self {
        Self(Utf8PathBuf::from(path.as_ref()))
    }

    /// The underlying path as a string.
    pub fn as_str(&self) -> &str {
        self.0.as_str()
    }
}

impl fmt::Display for PathLua {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.0.as_str())
    }
}

impl PartialEq for PathLua {
    fn eq(&self, other: &Self) -> bool {
        self.0 == other.0
    }
}

impl Eq for PathLua {}

impl PartialOrd for PathLua {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for PathLua {
    fn cmp(&self, other: &Self) -> Ordering {
        self.0.cmp(&other.0)
    }
}

impl UserData for PathLua {
    fn add_fields<F: LuaUserDataFields<Self>>(fields: &mut F) {
        fields.add_meta_field(LuaMetaMethod::Type, TYPE_NAME);
    }

    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("is_absolute", |_, this, ()| Ok(this.0.is_absolute()));
        methods.add_method("is_relative", |_, this, ()| Ok(this.0.is_relative()));
        methods.add_method("has_root", |_, this, ()| Ok(this.0.has_root()));

        methods.add_method("parent", |_, this, ()| {
            Ok(this.0.parent().map(|parent| PathLua(parent.to_path_buf())))
        });
        methods.add_method("ancestors", |lua, this, ()| {
            lua.create_sequence_from(
                this.0
                    .ancestors()
                    .map(|ancestor| PathLua(ancestor.to_path_buf())),
            )
        });

        methods.add_method("file_name", |_, this, ()| {
            Ok(this.0.file_name().map(str::to_owned))
        });
        methods.add_method("file_stem", |_, this, ()| {
            Ok(this.0.file_stem().map(str::to_owned))
        });
        methods.add_method("extension", |_, this, ()| {
            Ok(this.0.extension().map(str::to_owned))
        });

        methods.add_method("join", |_, this, args: LuaMultiValue| {
            // Argument 1 is `self`, so the first joined segment is argument 2.
            if args.is_empty() {
                return Err(bad_argument(
                    2,
                    "...",
                    "join",
                    &format!("string or {TYPE_NAME} expected"),
                ));
            }

            let mut joined = this.0.clone();
            for (offset, value) in args.iter().enumerate() {
                if let Some(segment) = path_argument(value, offset + 2, "...", "join")? {
                    append_segment(&mut joined, &segment);
                }
            }
            Ok(PathLua(joined))
        });

        methods.add_method("with_file_name", |_, this, file_name: LuaValue| {
            let file_name = string_argument(&file_name, 2, "file_name", "with_file_name")?;
            Ok(PathLua(this.0.with_file_name(file_name)))
        });
        methods.add_method("with_extension", |_, this, extension: LuaValue| {
            let extension = string_argument(&extension, 2, "extension", "with_extension")?;
            if extension_has_separator(&extension) {
                return Err(LuaError::runtime(EXTENSION_SEPARATOR_ERROR));
            }
            Ok(PathLua(this.0.with_extension(extension)))
        });
        methods.add_method("with_added_extension", |_, this, extension: LuaValue| {
            let extension = string_argument(&extension, 2, "extension", "with_added_extension")?;
            if extension_has_separator(&extension) {
                return Err(LuaError::runtime(EXTENSION_SEPARATOR_ERROR));
            }
            Ok(PathLua(this.0.with_added_extension(extension)))
        });

        methods.add_method("starts_with", |_, this, base: LuaValue| {
            let base = string_argument(&base, 2, "base", "starts_with")?;
            Ok(this.0.starts_with(&base))
        });
        methods.add_method("ends_with", |_, this, child: LuaValue| {
            let child = string_argument(&child, 2, "child", "ends_with")?;
            Ok(this.0.ends_with(&child))
        });
        methods.add_method("strip_prefix", |_, this, prefix: LuaValue| {
            let prefix = string_argument(&prefix, 2, "prefix", "strip_prefix")?;
            match this.0.strip_prefix(&prefix) {
                Ok(rest) => Ok(PathLua(rest.to_path_buf())),
                Err(_) => Err(LuaError::runtime("prefix not found")),
            }
        });

        // `Path:components() -> { kind = string, value = string }[]`
        methods.add_method("components", |lua, this, ()| {
            let table = lua.create_table()?;
            for (index, component) in this.0.components().enumerate() {
                let entry = lua.create_table_with_capacity(0, 2)?;
                entry.set("kind", component_kind(&component))?;
                entry.set("value", component.as_str())?;
                table.raw_set(index + 1, entry)?;
            }
            Ok(table)
        });

        methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| {
            Ok(this.0.to_string())
        });
        methods.add_meta_method(LuaMetaMethod::Eq, |_, this, other: LuaValue| {
            Ok(other
                .as_userdata()
                .and_then(|userdata| userdata.borrow::<PathLua>().ok())
                .is_some_and(|other| *this == *other))
        });
        methods.add_meta_method(
            LuaMetaMethod::Lt,
            |_, this, other: LuaUserDataRef<PathLua>| Ok(*this < *other),
        );
        methods.add_meta_method(
            LuaMetaMethod::Le,
            |_, this, other: LuaUserDataRef<PathLua>| Ok(*this <= *other),
        );

        // Python-style `/`: join the right operand onto this path.
        methods.add_meta_method(LuaMetaMethod::Div, |_, this, other: LuaValue| {
            let segment = match &other {
                LuaValue::String(text) => text.to_str().ok().map(|text| text.to_owned()),
                LuaValue::UserData(userdata) => userdata
                    .borrow::<PathLua>()
                    .ok()
                    .map(|path| path.0.as_str().to_owned()),
                _ => None,
            }
            .ok_or_else(|| {
                LuaError::runtime(format!(
                    "attempt to perform arithmetic on a {} value ({TYPE_NAME} / string or {TYPE_NAME} expected)",
                    other.type_name()
                ))
            })?;

            let mut joined = this.0.clone();
            append_segment(&mut joined, &segment);
            Ok(PathLua(joined))
        });
    }
}

/// The `luastd.path` module.
pub struct Path;

impl Module for Path {
    const NAME: &'static str = "luastd.path";

    fn create(lua: &Lua) -> LuaResult<Table> {
        let module = lua.create_table()?;
        module.set("new", lua.create_function(path_new)?)?;
        module.set("join", lua.create_function(path_join)?)?;
        Ok(module)
    }
}

/// `path.new(...) -> Path`
fn path_new(_: &Lua, args: LuaMultiValue) -> LuaResult<PathLua> {
    Ok(PathLua(join_segments(&collect_segments(&args, "new")?)))
}

/// `path.join(...) -> string`
fn path_join(_: &Lua, args: LuaMultiValue) -> LuaResult<String> {
    if args.is_empty() {
        return Err(bad_argument(
            1,
            "...",
            "join",
            &format!("string or {TYPE_NAME} expected"),
        ));
    }

    Ok(join_segments(&collect_segments(&args, "join")?).into_string())
}

/// Read every argument as a string or `Path`, skipping `nil`.
fn collect_segments(args: &LuaMultiValue, function: &str) -> LuaResult<Vec<String>> {
    let mut segments = Vec::new();
    for (offset, value) in args.iter().enumerate() {
        if let Some(segment) = path_argument(value, offset + 1, "...", function)? {
            segments.push(segment);
        }
    }
    Ok(segments)
}

/// Read a string or `Path` argument, returning `None` for `nil`.
pub fn path_argument(
    value: &LuaValue,
    index: usize,
    name: &str,
    function: &str,
) -> LuaResult<Option<String>> {
    match value {
        LuaValue::Nil => Ok(None),
        LuaValue::String(text) => match text.to_str() {
            Ok(text) => Ok(Some(text.to_owned())),
            Err(_) => Err(bad_argument(index, name, function, "UTF-8 string expected")),
        },
        LuaValue::UserData(userdata) => match userdata.borrow::<PathLua>() {
            Ok(path) => Ok(Some(path.0.as_str().to_owned())),
            Err(_) => Err(bad_argument(
                index,
                name,
                function,
                &format!("string or {TYPE_NAME} expected"),
            )),
        },
        _ => Err(bad_argument(
            index,
            name,
            function,
            &format!("string or {TYPE_NAME} expected"),
        )),
    }
}

/// Append a non-empty segment, letting an absolute segment reset the path.
fn append_segment(path: &mut Utf8PathBuf, segment: &str) {
    if !segment.is_empty() {
        path.push(segment);
    }
}

/// Join segments left to right, skipping empty ones.
fn join_segments(segments: &[String]) -> Utf8PathBuf {
    let mut path = Utf8PathBuf::new();
    for segment in segments {
        append_segment(&mut path, segment);
    }
    path
}

/// Check whether an extension contains a platform path separator.
fn extension_has_separator(extension: &str) -> bool {
    extension.chars().any(std::path::is_separator)
}

/// Map a camino component to its Lua `kind`.
fn component_kind(component: &Utf8Component<'_>) -> &'static str {
    match component {
        Utf8Component::Prefix(_) => "prefix",
        Utf8Component::RootDir => "root",
        Utf8Component::CurDir => "curdir",
        Utf8Component::ParentDir => "parentdir",
        Utf8Component::Normal(_) => "normal",
    }
}
