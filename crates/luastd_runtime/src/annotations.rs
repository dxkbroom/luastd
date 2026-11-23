//! Publish EmmyLua annotations for everything a runtime can `require`.
//!
//! The stubs are embedded at compile time, so a host can write them next to
//! its user's config and point emmylua_ls at them:
//!
//! ```no_run
//! # fn main() -> std::io::Result<()> {
//! let library = std::path::Path::new("/home/me/.config/myapp/library");
//! luastd_runtime::annotations::write(library)?;
//! luastd_runtime::annotations::merge_emmyrc("/home/me/.config/myapp/.emmyrc.json", library)?;
//! # Ok(())
//! # }
//! ```

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use serde_json::{Map, Value};

/// Stubs owned by this crate; effect modules' stubs follow their features.
const RUNTIME_DEFINITIONS: &[(&str, &str)] = &[
    (
        "luastd/error.lua",
        include_str!("../definitions/luastd/error.lua"),
    ),
    (
        "luastd/async.lua",
        include_str!("../definitions/luastd/async.lua"),
    ),
    #[cfg(feature = "env")]
    (
        "luastd/env.lua",
        include_str!("../definitions/luastd/env.lua"),
    ),
    #[cfg(feature = "fs")]
    (
        "luastd/fs.lua",
        include_str!("../definitions/luastd/fs.lua"),
    ),
    #[cfg(feature = "process")]
    (
        "luastd/process.lua",
        include_str!("../definitions/luastd/process.lua"),
    ),
];

/// Every stub as `(path relative to a library root, contents)`: the floor's
/// ([`luastd::DEFINITIONS`]) plus this crate's, for the compiled-in modules.
pub fn definitions() -> impl Iterator<Item = (&'static str, &'static str)> {
    luastd::DEFINITIONS
        .iter()
        .chain(RUNTIME_DEFINITIONS)
        .copied()
}

/// Write every stub under `dir` (created if missing), overwriting files with
/// the same names and leaving other files alone. Returns the written paths.
pub fn write(dir: impl AsRef<Path>) -> io::Result<Vec<PathBuf>> {
    let dir = dir.as_ref();
    let mut written = Vec::new();
    for (relative, contents) in definitions() {
        let path = dir.join(relative);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&path, contents)?;
        written.push(path);
    }
    Ok(written)
}

/// Add `library` to `workspace.library` in the `.emmyrc.json` at `emmyrc`.
///
/// Creates the file when missing. Every other key, and the order of existing
/// keys, is preserved; `library` is added once, compared as written.
pub fn merge_emmyrc(emmyrc: impl AsRef<Path>, library: impl AsRef<Path>) -> io::Result<()> {
    let emmyrc = emmyrc.as_ref();
    let library = library.as_ref().to_string_lossy().into_owned();

    let mut root = match fs::read_to_string(emmyrc) {
        Ok(text) if !text.trim().is_empty() => serde_json::from_str::<Value>(&text)
            .map_err(|error| invalid(emmyrc, &error.to_string()))?,
        Ok(_) => Value::Object(Map::new()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Value::Object(Map::new()),
        Err(error) => return Err(error),
    };

    let libraries = root
        .as_object_mut()
        .ok_or_else(|| invalid(emmyrc, "top level is not an object"))?
        .entry("workspace")
        .or_insert_with(|| Value::Object(Map::new()))
        .as_object_mut()
        .ok_or_else(|| invalid(emmyrc, "`workspace` is not an object"))?
        .entry("library")
        .or_insert_with(|| Value::Array(Vec::new()))
        .as_array_mut()
        .ok_or_else(|| invalid(emmyrc, "`workspace.library` is not an array"))?;

    if !libraries
        .iter()
        .any(|entry| entry.as_str() == Some(library.as_str()))
    {
        libraries.push(Value::String(library));
    }

    if let Some(parent) = emmyrc
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        fs::create_dir_all(parent)?;
    }
    let mut text = serde_json::to_string_pretty(&root).map_err(io::Error::other)?;
    text.push('\n');
    fs::write(emmyrc, text)
}

fn invalid(path: &Path, reason: &str) -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidData,
        format!("{}: {reason}", path.display()),
    )
}
