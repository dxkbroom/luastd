# luastd - design record

luastd is a Lua standard library written in Rust (`luastd`), a runtime that
embeds it with permission-checked IO and structured async (`luastd_runtime`),
and a cdylib that exposes the pure modules to plain Lua (`luastd_lua`).
`GLOSSARY.md` holds the vocabulary and `docs/adr/` the hard-to-reverse
decisions.

## Goals

- Write the things we don't want to write twice in Lua once, in Rust.
- A host embeds the runtime and decides the Lua version, vendoring, effect
  modules, permissions and whether `package`/`debug` are exposed.
- Kotlin-style structured concurrency on top of mlua async: scopes, Jobs,
  Deferreds, Channels, cancellation that cannot be swallowed.
- Every module ships EmmyLua stubs, and the runtime can publish them and
  write or merge a `.emmyrc.json`.

## Non-goals

- PUC-Rio Lua 5.1 (ADR 0001). Targets: `luajit52` (primary), `luajit`, `lua52`-`lua55`.
- mlua `send` and multi-threaded Lua states (ADR 0002).
- An editor or plugin framework. `tinyvi` is an example, not a product.

## Crates

| Crate | Kind | Contents |
| --- | --- | --- |
| `luastd` | lib | Pure modules, `Module` trait, argument helpers. No deno, no IO. |
| `luastd_runtime` | lib | Builder, `EffectModule`, effect modules behind `fs`/`env`/`process` features, async, prompter, EmmyLua publishing; re-exports `mlua` 0.12. |
| `luastd_lua` | cdylib | `luaopen_luastd*` entry points for lux; picks `module` and the Lua version. |

Only leaf crates enable a Lua version, `vendored` or `module`, because cargo
unifies features: a library that picks one breaks every host that picks
another.

lux builds the cdylib with
`cargo build --target-dir=<dir> [--no-default-features] --features <features>,<lua> <cargo_extra_args>`
from the repo root and copies `target/<profile>/lib<name>.so` for each
`[build.modules]` entry, so `lux.toml` sets `cargo_extra_args = ["-p", "luastd_lua"]`.

## Runtime shape

```rust
let rt = luastd_runtime::Runtime::builder()   // pure modules: always installed
    .permissions(perms)                        // Builder<WithPermissions>
    .prompter(MyPrompter)                      // optional, async (ADR 0004)
    .effect::<Fs>()
    .effect::<Process>()
    .build()?;
rt.run(async |lua| {
    lua.load(init_lua).exec_async().await?;    // implicit root scope
    host_loop(lua).await
})?;
```

## Lua API sketch

```lua
local path    = require("luastd.path")   -- floor: always present
local async   = require("luastd.async")
local fs      = require("luastd.fs")     -- effect: host feature + permission
local env     = require("luastd.env")
local process = require("luastd.process")

async.launch(fn)                -- Job: cancel(), is_active(); async.join(job)
async.async(fn)                 -- Deferred: async.await(d), async.try_await(d)
async.try_scope(fn)             -- ok, values... | false, err
async.scope(fn)                 -- waits for children; a failure cancels siblings
async.supervisor_scope(fn)      -- children fail independently
async.with_timeout(ms, fn)
async.delay(ms)
async.channel(cap?)             -- Channel: send, receive, close, iter, debounce(ms)
async.debounce(ms, fn)          -- wrapper bound to the creating scope
async.throttle(ms, fn)
async.finally(fn, cleanup)      -- cleanup also runs on cancellation (ADR 0005)

fs.read(p) / fs.write(p, s) / fs.list(p) / fs.stat(p)   -- ---@async, raise luastd.FsError
fs.read_sync(p) ...                                      -- blocking, for startup config
fs.try_read(p)                  -- ---@return_overload true, string / false, luastd.FsError
process.run(cmd, args, opts)    -- { code, stdout, stderr }, ---@async
process.spawn(cmd, args, opts)  -- Process: lines() -> Channel, wait(), kill()
```

Errors are tables with `kind`, `message` and context such as `path`; a denied
permission raises `kind = "PermissionDenied"`.

## tinyvi example

A small ratatui modal editor under `examples/tinyvi`, unpublished. A plugin is a
module returning `function(plugin)`; tinyvi calls it in a fresh supervisor
scope. The `tinyvi.Plugin` handle has `name`, `config`, `scope`, `log`, `on`,
`command`, `keymap` and `on_unload`; unloading cancels the scope and removes
everything registered through the handle. It demonstrates `:Grep` streaming
`process.spawn("rg")` into a panel, `:bd` cancelling the buffer's scope,
permission prompts drawn as a modal, and autosave via `async.debounce`.

## Stack

Bottom to top. Each layer builds, passes `mise run test` and `mise run lint`.

1. **`luastd/docs`** - ADRs 0001-0005, `GLOSSARY.md`, `AGENTS.md`, this plan.
   Done: docs merged; no code changes.
2. **`luastd/workspace`** - cargo workspace with the three crates; existing
   `path` module moves to `luastd`, the entry points to `luastd_lua`; mlua 0.12;
   kbstd renamed to luastd across lux, rockspec, specs, stubs and tasks.
   Done: `lx test` passes against the cdylib built from `crates/luastd_lua`.
3. **`luastd/pure`** - `Module` trait, argument helpers, `clippy.toml`
   disallowed methods; pure modules ported from the earlier attempt where they
   still fit (`formatx`, `semver`; `math` was dropped) with stubs and specs.
   Done: each module has stubs, specs and Rust tests; clippy proves no IO.
4. **`luastd/runtime`** - `Runtime`, typestate builder, preload installation,
   sandboxed globals, executor (ADR 0003), `EffectModule`, permissions,
   EmmyLua publishing and `.emmyrc.json` merge.
   Done: a Rust test embeds the runtime with only the floor and `require`s it;
   `io`/`os.execute` are absent.
5. **`luastd/env`** - `luastd.env` behind the `env` feature, permission-checked,
   and the async prompter (ADR 0004), moved here from layer 4 because env is its
   first consumer. Done: allowed, denied and prompted reads covered by tests.
6. **`luastd/async`** - scope, supervisor scope, Job, Deferred, Channel,
   timeout, delay, debounce, throttle, finally, cancellation-aware `pcall`
   (ADR 0005). Done: cancellation through `pcall`, sibling cancellation and
   supervisor isolation are tested.
7. **`luastd/fs`** - async `luastd.fs`, `*_sync` and `try_*` variants,
   structured errors. Done: permission denial and `return_overload` stubs checked.
8. **`luastd/tinyvi`** - `luastd.process` and the `tinyvi` example.
   Done: grep, `:bd` cancellation, prompts and autosave work by hand.

Review checkpoints: after layer 2, after layer 4, after layer 6.

## Deferred

- Cold `Flow` and operator chains such as `flow:debounce(ms):map(f)`:
  a large, on-demand track; design with an ADR before starting.
  [#1](https://github.com/dxkbroom/luastd/issues/1).
- A lower-level "drive it from your own loop" API next to `Runtime::run`.
