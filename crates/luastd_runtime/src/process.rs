//! The `luastd.process` effect module (cargo feature `process`).
//!
//! Spawns child processes through permission checks. Every command name is
//! checked against the host's `run` permission. The plain functions are
//! `---@async`: when the host has not decided yet they await the host's
//! [`Prompter`](crate::Prompter). The `*_sync` variants never prompt; an
//! undecided permission raises `PermissionDenied`.

use std::cell::RefCell;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, Ordering};

use deno_permissions::PermissionsContainer;
use mlua::{Lua, MultiValue, Result as MluaResult, Table, Value};

use crate::EffectModule;
use crate::errors::LuaError;
use crate::prompt::{Descriptor, check};

#[cfg(feature = "env")]
use crate::env::EnvOverlay;

/// The `luastd.process` module.
pub struct Process;

#[derive(Clone)]
pub(crate) struct ProcessDescriptor(pub String);

impl Descriptor for ProcessDescriptor {
    const PERMISSION: &'static str = "run";

    fn target(&self) -> Option<String> {
        Some(self.0.clone())
    }

    fn query(&self, container: &PermissionsContainer) -> deno_permissions::PermissionState {
        container
            .query_run(Some(&self.0))
            .unwrap_or(deno_permissions::PermissionState::Denied)
    }

    fn request(&self, container: &PermissionsContainer) -> deno_permissions::PermissionState {
        container
            .request_run(Some(&self.0))
            .unwrap_or(deno_permissions::PermissionState::Denied)
    }

    fn check(&self, container: &PermissionsContainer) -> Result<(), String> {
        use deno_permissions::RunQueryDescriptor;
        container
            .check_run(&RunQueryDescriptor::Name(self.0.clone()), "luastd.process")
            .map_err(|error| error.to_string())
    }
}

// ---------- options ----------

#[derive(Default, Clone)]
struct ProcessOpts {
    cwd: Option<std::path::PathBuf>,
    env: Vec<(String, String)>,
    stdin: Option<String>,
}

pub struct ProcessHandle {
    pid: Option<u32>,
    code: i32,
    lines: Vec<String>,
    killed: Rc<AtomicBool>,
}

impl mlua::UserData for ProcessHandle {
    fn add_methods<M: mlua::UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("pid", |_, this, ()| Ok(this.pid.map(|p| p as i64)));

        methods.add_method("lines", |lua, this, ()| {
            let lines = this.lines.clone();
            let index = Rc::new(RefCell::new(0usize));
            lua.create_function(move |_, ()| {
                let mut i = index.borrow_mut();
                if *i < lines.len() {
                    let line = lines[*i].clone();
                    *i += 1;
                    Ok(Some(line))
                } else {
                    Ok(None::<String>)
                }
            })
        });

        methods.add_method("wait", |_, this, ()| Ok(this.code));

        methods.add_method("kill", |_, this, ()| {
            this.killed.store(true, Ordering::SeqCst);
            Ok(())
        });
    }
}

// ---------- argument helpers ----------

fn bad_argument(index: usize, name: &str, function: &str, expected: &str) -> LuaError {
    LuaError::new(
        "InvalidArgument",
        format!("bad argument #{index} '{name}' to '{function}' ({expected})"),
    )
}

fn string_arg(
    args: &MultiValue,
    index: usize,
    function: &str,
) -> std::result::Result<String, LuaError> {
    match args.get(index - 1) {
        Some(Value::String(text)) => text
            .to_str()
            .map(|s| s.to_owned())
            .map_err(|_| bad_argument(index, "command", function, "UTF-8 string expected")),
        _ => Err(bad_argument(index, "command", function, "string expected")),
    }
}

fn is_opts_table(table: &Table) -> bool {
    table.contains_key("cwd").unwrap_or(false)
        || table.contains_key("env").unwrap_or(false)
        || table.contains_key("stdin").unwrap_or(false)
}

fn parse_args_table(table: &Table, function: &str) -> std::result::Result<Vec<String>, LuaError> {
    let mut out = Vec::new();
    let mut i = 1i64;
    loop {
        match table.get::<Value>(i) {
            Ok(Value::Nil) => break,
            Ok(Value::String(s)) => {
                let text = s
                    .to_str()
                    .map_err(|_| bad_argument(2, "args", function, "UTF-8 string expected"))?;
                out.push(text.to_owned());
            }
            Ok(other) => {
                // allow tostring
                let text = other
                    .to_string()
                    .map_err(|_| bad_argument(2, "args", function, "string expected"))?;
                out.push(text);
            }
            Err(_) => break,
        }
        i += 1;
    }
    Ok(out)
}

fn parse_env_table(table: &Table, function: &str) -> Result<Vec<(String, String)>, LuaError> {
    let mut out = Vec::new();
    for pair in table.pairs::<Value, Value>() {
        let (k, v) = pair.map_err(|e| LuaError::new("InvalidArgument", e.to_string()))?;
        let key = match k {
            Value::String(s) => s
                .to_str()
                .map_err(|_| bad_argument(0, "env", function, "UTF-8 key expected"))?
                .to_owned(),
            other => other
                .to_string()
                .map_err(|_| bad_argument(0, "env", function, "string key expected"))?,
        };
        let value = match v {
            Value::String(s) => s
                .to_str()
                .map_err(|_| bad_argument(0, "env", function, "UTF-8 value expected"))?
                .to_owned(),
            other => other.to_string().unwrap_or_default(),
        };
        out.push((key, value));
    }
    Ok(out)
}

fn parse_opts(table: &Table, function: &str) -> std::result::Result<ProcessOpts, LuaError> {
    let mut opts = ProcessOpts::default();
    if let Ok(Value::String(s)) = table.get::<Value>("cwd") {
        let text = s
            .to_str()
            .map_err(|_| bad_argument(0, "cwd", function, "UTF-8 string expected"))?;
        opts.cwd = Some(std::path::PathBuf::from(text.to_owned()));
    } else if let Ok(Value::UserData(_)) = table.get::<Value>("cwd") {
        let value: Value = table.get("cwd").unwrap();
        let text = value
            .to_string()
            .map_err(|_| bad_argument(0, "cwd", function, "path expected"))?;
        if !text.is_empty() {
            opts.cwd = Some(std::path::PathBuf::from(text.to_owned()));
        }
    }
    if let Ok(Value::Table(t)) = table.get::<Value>("env") {
        opts.env = parse_env_table(&t, function)?;
    }
    if let Ok(Value::String(s)) = table.get::<Value>("stdin") {
        let text = s
            .to_str()
            .map_err(|_| bad_argument(0, "stdin", function, "UTF-8 string expected"))?;
        opts.stdin = Some(text.to_owned());
    }
    Ok(opts)
}

fn parse_call(
    args: &MultiValue,
    function: &str,
) -> std::result::Result<(String, Vec<String>, ProcessOpts), LuaError> {
    let cmd = string_arg(args, 1, function)?;
    let mut arg_list = Vec::new();
    let mut opts = ProcessOpts::default();
    let mut idx = 2usize;
    if let Some(Value::Table(t)) = args.get(1) {
        if is_opts_table(t) {
            opts = parse_opts(t, function)?;
            idx = 3;
        } else {
            arg_list = parse_args_table(t, function)?;
            idx = 3;
        }
    }
    if let Some(Value::Table(t)) = args.get(idx - 1) {
        opts = parse_opts(t, function)?;
    }
    let _ = idx;
    Ok((cmd, arg_list, opts))
}

// ---------- execution ----------

async fn run_command(
    lua: &Lua,
    cmd_name: String,
    args: Vec<String>,
    opts: ProcessOpts,
) -> std::result::Result<(Option<u32>, i32, String, String), LuaError> {
    let _ = lua;
    let mut command = tokio::process::Command::new(&cmd_name);
    command.args(&args);
    if let Some(cwd) = &opts.cwd {
        command.current_dir(cwd);
    }
    #[cfg(feature = "env")]
    {
        if let Some(overlay) = lua.app_data_ref::<EnvOverlay>() {
            for (k, v) in overlay.vars() {
                command.env(k, v);
            }
        }
    }
    for (k, v) in &opts.env {
        command.env(k, v);
    }
    command.stdout(std::process::Stdio::piped());
    command.stderr(std::process::Stdio::piped());
    if opts.stdin.is_some() {
        command.stdin(std::process::Stdio::piped());
    } else {
        command.stdin(std::process::Stdio::null());
    }

    let mut child = command
        .spawn()
        .map_err(|e| LuaError::new("ProcessError", format!("spawn: {e}")))?;
    let pid = child.id();

    if let Some(stdin_data) = &opts.stdin
        && let Some(mut stdin) = child.stdin.take()
    {
        use tokio::io::AsyncWriteExt;
        let _ = stdin.write_all(stdin_data.as_bytes()).await;
        drop(stdin);
    }

    let output = child
        .wait_with_output()
        .await
        .map_err(|e| LuaError::new("ProcessError", format!("wait: {e}")))?;

    let code = output.status.code().unwrap_or(-1);
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    Ok((pid, code, stdout, stderr))
}


fn make_result_table(lua: &Lua, code: i32, stdout: String, stderr: String) -> MluaResult<Value> {
    let table = lua.create_table()?;
    table.set("code", code)?;
    table.set("stdout", stdout)?;
    table.set("stderr", stderr)?;
    Ok(Value::Table(table))
}

impl EffectModule for Process {
    const NAME: &'static str = "luastd.process";

    fn create(lua: &Lua, permissions: &PermissionsContainer) -> MluaResult<Table> {
        let module = lua.create_table()?;

        // run
        {
            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move {
                    let (cmd, args, opts) = parse_call(&args, "run")?;
                    check(&lua, &perms, ProcessDescriptor(cmd.clone())).await?;
                    let (_pid, code, stdout, stderr) = run_command(&lua, cmd, args, opts).await?;
                    make_result_table(&lua, code, stdout, stderr)
                }
            })?;
            module.set("run", f)?;

            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move {
                    match (|| async {
                        let (cmd, args, opts) = parse_call(&args, "run")?;
                        check(&lua, &perms, ProcessDescriptor(cmd.clone())).await?;
                        let (_pid, code, stdout, stderr) =
                            run_command(&lua, cmd, args, opts).await?;
                        make_result_table(&lua, code, stdout, stderr)
                    })()
                    .await
                    {
                        Ok(v) => {
                            let mut mv = MultiValue::new();
                            mv.push_back(Value::Boolean(true));
                            mv.push_back(v);
                            Ok(mv)
                        }
                        Err(e) => {
                            if let Some(le) = LuaError::find(&e)
                                && le.kind() == "Cancelled"
                            {
                                return Err(e);
                            }
                            let table = match LuaError::find(&e) {
                                Some(le) => le.table(&lua)?,
                                None => LuaError::new("ProcessError", e.to_string()).table(&lua)?,
                            };
                            let mut mv = MultiValue::new();
                            mv.push_back(Value::Boolean(false));
                            mv.push_back(Value::Table(table));
                            Ok(mv)
                        }
                    }
                }
            })?;
            module.set("try_run", f)?;
        }

        // spawn
        {
            let perms = permissions.clone();
            let f = lua.create_async_function(move |lua, args: MultiValue| {
                let perms = perms.clone();
                async move {
                    let (cmd, args, opts) = parse_call(&args, "spawn")?;
                    check(&lua, &perms, ProcessDescriptor(cmd.clone())).await?;
                    let (pid, code, stdout, _stderr) = run_command(&lua, cmd, args, opts).await?;
                    let lines: Vec<String> = stdout.lines().map(|s| s.to_owned()).collect();
                    let handle = ProcessHandle {
                        pid,
                        code,
                        lines,
                        killed: Rc::new(AtomicBool::new(false)),
                    };
                    lua.create_userdata(handle)
                }
            })?;
            module.set("spawn", f)?;
        }

        Ok(module)
    }
}
