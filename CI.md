# CI considerations

The Python xtasks use Tree-sitter to read Lua port specs and Kotlin test sources.
`tree-sitter-language-pack` supplies the Lua and Kotlin grammars and downloads
their parser libraries on first use. The package is locked in
`xtasks/uv.lock`; parser libraries have a separate local cache.

If CI is added later, account for that cache explicitly:

- Allow network access during the first parser load, or download the `lua` and
  `kotlin` grammars during setup.
- Cache the Tree-sitter language-pack `libs` directory between runs. On Linux,
  its default location is `~/.cache/tree-sitter-language-pack/v<version>/libs`;
  the version segment means the cache key should include the language-pack
  version, OS, and architecture.
- Run `mise run kotlin:check -- --check` and `mise run lint` after parser setup
  so both the coverage inventory and normal lint path exercise the grammars.

The current local workflow relies on the language pack's default cache and does
not configure a CI cache or parser prefetch step.
