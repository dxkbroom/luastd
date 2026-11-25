# Repository Agent Guide

`luastd` is a Lua standard library written in Rust, plus a runtime that embeds
it with permission-checked IO and structured async. It is a library and a
runtime, not an editor or an application framework: stay on the std modules,
the runtime, and exposing both to Lua.

`PLAN.md` is the design record and the stack plan. `GLOSSARY.md` defines the
domain vocabulary. `docs/adr/` records decisions that are hard to reverse.

## Commands

`<target>` is a Lua version: `luajit52` (default, ADR 0001), `luajit`, `lua52`
to `lua55`.

- `mise run build [target]` / `mise run b` - `cargo build` the workspace for one Lua version
- `mise run test [target]` / `mise run t` - all tests
- `mise run test:unit [target]` - `cargo test`, then `lx test` (busted specs in `spec/`)
- `mise run kotlin:check [--check]` - which kotlinx.coroutines tests the Kotlin
  ports cover (needs the checkout in `$KOTLINX_DIR`, default `../kotlinx.coroutines`)
- `mise run kotlin:report [--json|--markdown] [--check]` - full Kotlin test
  inventory and port coverage report
- `mise run kotlin:format [files...]` - reorder Lua test blocks to match Kotlin source order
- `mise run kotlin:stubs [--dry-run]` - generate pending Lua specs for unported
  Kotlin test classes and register them in the Rust test target
- `mise run lint [target]` / `mise run check` - rumdl, tombi, `cargo clippy`, `emmylua_check`
- `mise run fmt` / `mise run format` - cargo fmt, rumdl fmt, tombi format, luafmt
- `mise run example` - run `crates/luastd_runtime/examples/hello.rs` (vendored luajit52)
- `mise run fork:build` - rebuild the local emmylua-analyzer-rust fork
- `mise run nvim:build` - build the cdylib for Neovim's LuaJIT into `target/nvim`, loaded by `.lazy.lua`
- `mise run clean` - `cargo clean`

Run `mise run fmt` and `mise run lint` before committing.

## Layout

- `crates/luastd/` - pure modules (`luastd.path`, ...); no IO, no deno.
- `crates/luastd_runtime/` - the embedding runtime: builder, effect modules
  behind cargo features (`fs`, `env`, `process`), async, permissions; re-exports
  the pinned `mlua`.
- `crates/luastd_lua/` - the cdylib (`luaopen_luastd`, `luaopen_luastd_path`, ...)
  built by lux for plain Lua consumers.
- `crates/luastd/definitions/luastd/` - EmmyLua `---@meta` stubs for the
  pure modules in `require` layout (`init.lua`, `path.lua`, ...), embedded as
  `luastd::DEFINITIONS`. `luastd.<name>.lua`-style file names make emmylua resolve
  `require("luastd.<name>")` to a builtin of the same name.
- `crates/luastd_runtime/src/async.lua` - the Lua half of `luastd.async` over
  the Rust core in `scheduler.rs`; it also defines the replacement `pcall`/`xpcall`.
- `crates/luastd_runtime/definitions/luastd/` - stubs for the runtime's
  modules and error types, chained after the floor's by `annotations::definitions`.
- `spec/` - busted specs, run by `lx test` against the cdylib.
- `crates/luastd_runtime/tests/lua/` - busted-shaped specs for runtime modules,
  run inside a `Runtime` by `tests/common` with `harness.lua` (busted itself
  needs `io`, which the sandbox removes) and `luastd_test.lua`
  (`require("luastd_test")`: `runtest`, test-only). `kotlinx/` holds the Kotlin
  test ports, run by `tests/kotlinx.rs`.
- `examples/tinyvi/` - small ratatui modal editor exercising the runtime; not published.
- `xtasks/tasks/` - mise file tasks.
- `.lazy.lua`, `.nvim/` - Neovim dev setup: the emmylua fork, `require("luastd")`
  from this checkout, `:Luastd [module] [example]` (`.nvim/examples.lua`), and
  module navigation under `<leader>p` (`<leader>pgk`: from a Kotlin test port to its Kotlin `fun`) with a neo-tree source (`.nvim/project.lua`,
  `.nvim/neotree.lua`). A module is its stub, `<module>.rs` and
  `luastd_<module>_spec.lua`.
- `lux.toml`, `luastd-*.rockspec` - Lua packaging; build `luastd_lua` via
  `cargo_extra_args = ["-p", "luastd_lua"]`.

## Design rules

- **Library crates never pick a Lua version.** Only leaf crates (the cdylib, a
  host, an example) enable `luajit52`/`lua5x`, `vendored` or `module`.
  `luastd_runtime` re-exports mlua but must not enable those features.
- **Pure modules are the floor.** They are data-only, live in `luastd`, are
  always installed, and cannot be opted out of. `clippy.toml` disallows
  `std::fs`, `std::env` and `std::process` there.
- **Effects are typed and permissioned.** `Module::create(lua)` for pure
  modules, `EffectModule::create(lua, &PermissionsContainer)` for effect modules.
  `.effect::<Fs>()` only exists on `Builder<WithPermissions>`. Cargo features
  decide what is compiled in; permissions decide what runs.
- **The runtime owns IO.** No builtin `io`; `os` keeps only `clock`, `date`,
  `difftime` and `time`; no `dofile`/`loadfile`/`loadstring`; `load` is
  text-only. `require` only sees `package.preload` unless the host calls
  `Builder::package(true)`; `debug` needs the `unsafe` `Builder::debug`.
  `luastd_runtime/src/sandbox.rs` is the single place that decides this.
- **`require`, not globals.** Modules are reached as `require("luastd.path")`
  through `package.preload`; nothing is added to `_G`.
- **`luastd_lua` is not a default member.** It forces mlua's `module` feature,
  which conflicts with `vendored` and cannot link test binaries; plain
  `cargo build`/`cargo test` skip it, and lux builds it with `-p luastd_lua`.
  Do not run `cargo test --workspace`.
- **One thread per Lua state** (ADR 0002). Use `Rc`/`RefCell`; never mlua `send`.
- **The runtime owns the executor** (ADR 0003): tokio current-thread plus a
  `LocalSet`; the host loop runs inside `rt.run`.
- **Prompts never block the Lua thread** (ADR 0004).
- **Cancellation is not catchable by `pcall`** (ADR 0005).
- **Errors are `luastd.Error` tables** that keep their identity through Rust
  frames (ADR 0006); raise from Rust with `Err(LuaError::new(..).into())`.
- **Async is the blessed path.** Effect functions are `---@async` and raise
  structured errors; blocking variants are named `*_sync`; `try_*` variants
  return `ok, value | err`, are annotated with `---@return_overload` and never
  catch cancellation (ADR 0005, ADR 0008).
- **One canonical form per operation** (ADR 0007). Add another spelling only
  when it composes differently (prefix form, explicit receiver, `*_sync` or
  `try_*`, one-shot helper, operator); stubs mark the canonical form and
  cross-link the other.
- **luastd's own Lua is plain 5.1 + LuaJIT.** Stubs, specs and helpers must not
  rely on 5.2-compat additions, so they run on a Neovim-style `luajit`.

## Kotlin test ports

`luastd.async` follows kotlinx.coroutines, so its behaviour is tested by
porting kotlinx.coroutines 1.11.0's tests (`kotlinx-coroutines-core/common/test`).
Our own specs keep the `luastd_<module>_spec.lua` convention; ports are kept apart
so each reads next to its Kotlin source:

- One file per Kotlin class: `crates/luastd_runtime/tests/lua/kotlinx/<Class>.lua`,
  listed in `kotlinx!` in `tests/kotlinx.rs` (one `#[test]` per class, in a
  fresh runtime: `cargo test --test kotlinx WithTimeoutTest`).
- Directly above the top-level `describe`, a `-- kotlin: <path>@<tag>` line
  (e.g. `-- kotlin: kotlinx-coroutines-core/common/test/WithTimeoutTest.kt@1.11.0`).
  The `describe` is the Kotlin class name; each `it` is the Kotlin `fun` name,
  unchanged.
- Every Kotlin `@Test` appears once, as one of:
  - `it(name, runtest(...))` - ported;
  - the same with a `-- adapted: <why>` comment above - ported with a deliberate
    difference;
  - `pending(name)` with `-- deprecated: <why>` when the Kotlin test exercises
    an API deprecated by kotlinx.coroutines (separate from runtime applicability);
  - `pending(name)` with `-- todo: <why>` (an unported case that can be worked
    on with the current API);
  - `pending(name)` with `-- defer: <why>` when review has confirmed that the
    current API cannot support the case;
  - `pending(name)` with `-- not-applicable: <why>` when the Kotlin case does
    not apply to luastd (e.g. ADR 0005).

  One mark above the first `pending` of a contiguous run covers the whole run,
  so a block of cases that defer for the same reason shares one comment.
- Bind `local runtest = luastd_test.runtest` and call `runtest(function (t) ... end)`
  (mirrors `runTest { }`): `t:expect(n)`, `t:finish(n)`, `t:expect_unreached()`;
  options `expected`, `unhandled` (a luastd.Error kind, or a predicate) and
  `timeout` (default 10 s). The local alias needs emmylua with #1443
  (main-kbroom).
- Kotlin's `TimeoutCancellationException` is luastd's `Timeout` error kind;
  `TestException`/`1`/`2`/`3` are `luastd_test.TestException()` etc.
- `mise run kotlin:check` reports ported/adapted/deprecated/not-applicable/defer/todo/missing per class;
  `--check` fails on missing tests or names Kotlin does not have.

## Dependencies

`mlua` 0.12 (pinned and re-exported by `luastd_runtime`), `camino` 1,
`deno_permissions` 0.119 (runtime only), `tokio` (runtime only, current-thread).
Do not add a dependency to `luastd` that does IO. Crate names are snake_case.

## Workflow

This repository uses `gh stack` (see `.agents/skills/gh-stack/`). Work
bottom-up, one concern per layer:

```sh
gh stack init <layer>      # or: gh stack add <next-layer>, before writing its files
# git add <files> && git commit
gh stack submit --auto     # push every layer and open draft PRs
gh stack view --json
```

- Never force-push and never amend or rebase commits that are already pushed;
  add a new commit instead.
- Edit a lower layer by adding a commit on it, then merge upward
  (`git merge` into each higher branch, in order) and `git push`; never
  rewrite pushed branches.
- Use conventional commit subjects. Keep each layer reviewable on its own and
  green before moving up.
- PRs are opened under the `dxkbroom` GitHub account.
