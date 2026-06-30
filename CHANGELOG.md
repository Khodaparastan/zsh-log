# Changelog

All notable changes to `zlog` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Fixed
- **Loader no longer mutates the caller's shell.** Removed the file-scope `emulate zsh` and `setopt typeset_silent`; these reset/leaked options into the sourcing interactive shell. Per-function `emulate -L zsh` is sufficient.
- **Re-sourcing is now clean.** The readonly constants block is guarded with `${+_ZLOG_VERSION}`, so sourcing `zlog` more than once no longer raises `read-only variable` errors. ("Safe to source many times" now holds.)
- **Removed a duplicate `__z::log::engine_fast` definition.** The second, divergent copy silently shadowed the first; kept the version that gates file output on the maintained `_zlog_state[file_enabled]` flag.
- **`z::log::list_timers` elapsed time fixed.** It subtracted an integer-millisecond start time from the seconds-based `EPOCHREALTIME`, always yielding `<invalid>`; now uses the same millisecond clock.

### Changed
- **Context loggers are now eval-free.** `z::log::with_context` no longer `eval`s 8 full function bodies per context. A single shared dispatcher (`__z::log::ctx_dispatch`) holds all logic; each `${ctx}::info` / `infof` / … name is registered as a 1-line trampoline via `functions[name]=…` (no code generation) that forwards to it. Same UX and behavior, one source of truth, no per-context `eval`.
- **File-size checks are fork-free (big rotation win).** `__z::log::get_file_size` now prefers the in-process `zstat` builtin (`zsh/stat`) over a `stat(1)` fork, falling back to GNU/BSD `stat` and finally `wc -c`. Since `__z::log::rotate_if_needed` calls it on every file write, this removes a per-write fork: in the benchmark suite `get_file_size` dropped from ~3.2 ms/op to ~0.04 ms/op (~80x faster) and `rotate_if_needed no-op` fell proportionally.
- **Default text formatter is ~2x faster.** `__z::log::format_text` (the default-engine formatter, used by every non-fast log line) inlined four per-call cached-lookup helpers — `level_name`, `__z::sys::pid`, the named-color path of `z::log::colorize`, and the `str::repeat` padding — instead of calling them. Output is byte-identical across all color modes/levels; the no-field case dropped from ~115.7 µs/op to ~57.2 µs/op, bringing the default formatter on par with the fast-engine `format_simple`.
- **Default JSON formatter is ~2x faster.** `__z::log::format_json` was doing the same redundant per-line work the text formatter shed: it inlines the `level_name`/`pid` cached lookups, skips escaping the level label entirely (it is always one of the fixed ASCII labels `ERROR`/`WARN`/`INFO`/`DEBUG`/`UNKNOWN`, never JSON-special), and caches the JSON-escaped `hostname`/`username` (per-process constants) instead of re-escaping them on every line. Escaped forms are invalidated exactly via a source marker, so `z::log::clear_sys_cache` and runtime host/user changes still take effect. Output is byte-identical; the no-field case dropped from ~127 µs/op to ~65 µs/op and the 2-field case from ~221 µs/op to ~150 µs/op, matching `format_text`.
- **Startup is fork-free.** Removed eager `stat`/`gstat`/`strftime` probing from `__z::log::init_globals` (ran on every shell startup); capability detection is already lazy in `get_file_size` / `update_timestamp`.
- **Timestamp path avoids subshells.** Replaced `$(strftime …)` command substitutions with the no-fork `strftime -s` assign form; same for `benchmark_block`'s `eval "$(cat)"` → `eval "$(<&0)"`.
- Documented the async logging side effects (rotation is bypassed; async + buffering can interleave output) on `z::log::enable_async`.
- Corrected the `__z::log::format` doc comment to reflect REPLY-passing (it does not print to stdout).

### Tests
- Added a "Load Safety & Audit Regressions" section asserting no caller-option mutation on source, clean double-source, a single `engine_fast` definition, no `$(strftime)` command substitutions, and valid `list_timers` elapsed output.
- The unit/integration harnesses no longer rely on `err_return` (which was previously neutralized by the loader's option pollution and is incompatible with their accumulate-and-continue design).
- Extended the context-logger integration tests: the printf (`f`) variant formats correctly, and each per-context function is asserted to be a thin trampoline that forwards to the shared dispatcher (no inlined logic).
- Added `get_file_size` regression assertions (exact byte count, the fork-free `zstat` path is selected, and missing-file returns `1`).
- Added a `format_text` output regression test pinning the default formatter's exact structure (5-char level padding, `UNKNOWN` fallback, context-field tail, empty/missing-message return codes) so the inlining optimization can't silently change rendered output.
- Added a `format_json` output regression test pinning the JSON formatter's structure and escaping (level labels incl. `UNKNOWN`, required fields, message/value quote-and-backslash escaping, special-char hostname escaping, and re-escape on hostname change) so the inlining/caching optimization can't silently change rendered JSON.
- **Benchmark fix:** the context-call cases used the reserved/invalid context key `user`, so `with_context` silently failed and the suite was measuring a *command-not-found* (`::info`) at ~5 ms/op rather than the real dispatcher. Switched to a valid key (`user_id`) and added a guard that aborts the context cases if context creation fails.

---

## [1.0.0] — 2026-03-29

### Added
- Core logging engine with four levels: `error`, `warn`, `info`, `debug`
- Text and JSON output formatters
- Structured key-value fields on every log line
- Timestamp system with sub-second precision via `$EPOCHREALTIME`; cached per second to avoid repeated `strftime` calls
- File output with configurable path and independent file log level
- Log rotation: size-based, configurable max size (1 KB – 1 GB), configurable number of kept files (1–100)
- Multi-process-safe rotation via lock file with configurable timeout
- In-memory buffering with configurable buffer size and auto-flush on ERROR or buffer-full
- Exit hooks (zshexit / TRAPEXIT / trap EXIT) to guarantee buffer flush on process exit
- Printf-style API: `z::log::errorf`, `warnf`, `infof`, `debugf`
- `z::log::with_level` — temporarily change log level for a command or function
- `z::log::silent` — suppress all logging for a command or function
- `z::log::always` — force a log line regardless of current level
- `z::log::once` — log a message only the first time a given key is seen
- `z::log::rate_limit` — cap log output to N messages per T seconds per key
- Context loggers: `z::log::with_context` creates a named logger that auto-appends KV fields
- Benchmarking: `z::log::benchmark`, `benchmark_start`/`benchmark_end`, `benchmark_block`
- Async logging: FIFO + background worker subshell, graceful shutdown via sentinel
- Performance mode: hot-swaps the engine with a fast-path variant at runtime
- Color system: auto-detects `none` / `basic` / `256` / `truecolor`; respects `NO_COLOR`
- `z::log::setup` — one-call quick-start helper
- `z::log::show_config` — box-drawing table of all current settings
- `z::log::reset` — restore all defaults without re-sourcing
- `z::log::get_stats` / `show_stats` — runtime counters (messages logged, dropped, rotations, errors)
- `z::log::enable_debug_mode` — verbose internal tracing for library development
- Full re-entrancy: all globals guarded with `${+var}`; safe to source multiple times
- Recursion protection: max call depth of 5 to prevent infinite logging loops

---

[Unreleased]: https://github.com/khodaparastan/zsh-log/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/khodaparastan/zsh-log/releases/tag/v1.0.0
