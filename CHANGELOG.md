# Changelog

All notable changes to `zlog` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- Nothing yet.

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
