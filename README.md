# zsh-log


[![CI](https://img.shields.io/github/actions/workflow/status/khodaparastan/zlog/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/khodaparastan/zlog/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
[![Zsh 5.8+](https://img.shields.io/badge/zsh-5.8%2B-green?style=flat-square)](https://www.zsh.org/)
[![Single file](https://img.shields.io/badge/single%20file-zlog-orange?style=flat-square)](zlog)

**A high-performance, feature-rich logging library for Zsh with structured logging, contextual logging, benchmarking, and multiple output formats.**

---

## Why zsh-log?

Most Zsh scripts log with `echo`. That works until you need log levels, file output, JSON for log aggregators, rate limiting, or any kind of structure. `zlog` gives you all of that without leaving the shell.

- **Leveled output** — `error`, `warn`, `info`, `debug` with independent console and file thresholds
- **Structured fields** — append `key value` pairs to any log line, in text or JSON
- **File rotation** — size-based, multi-process safe, configurable retention
- **Context loggers** — create a named logger that auto-attaches fields to every message
- **Benchmarking** — wrap any command or block and get a formatted duration log line
- **Rate limiting & log-once** — prevent log floods in tight loops
- **Async mode** — non-blocking writes via a background worker
- **Performance mode** — hot-swap to a fast-path engine for hot loops
- **No dependencies** — pure Zsh 5.8+, single file, safe to re-source

---

## Install

```zsh
# Option 1 — copy the file
curl -fsSL https://raw.githubusercontent.com/khodaparastan/zsh-log/main/zlog -o zlog

# Option 2 — clone
git clone https://github.com/khodaparastan/zsh-log.git
```

Then source it:

```zsh
source /path/to/zlog
```

That's it. No package manager, no build step.

---

## Quick start

```zsh
source ./zlog

# Console only (default)
zlog::info  "Server started" port 8080 env production
zlog::warn  "High memory usage" used_mb 1800 limit_mb 2048
zlog::error "Connection refused" host db.internal retries 3

# With a log file
zlog::setup /var/log/myapp.log info text

# Switch to JSON (great for log aggregators)
zlog::set_format json
zlog::info "User login" user alice ip 10.0.0.1
```

**Text output:**
```
2026-03-15 14:23:01 [INFO ] (12345) Server started | port=8080 env=production
2026-03-15 14:23:01 [WARN ] (12345) High memory usage | used_mb=1800 limit_mb=2048
2026-03-15 14:23:01 [ERROR] (12345) Connection refused | host=db.internal retries=3
```

**JSON output:**
```json
{"timestamp":"2026-03-15T14:23:01Z","level":"INFO","message":"User login","pid":12345,"user":"alice","ip":"10.0.0.1"}
```

---

## Core API

```zsh
zlog::error "msg" [key val ...]   # level 0 — always shown
zlog::warn  "msg" [key val ...]   # level 1
zlog::info  "msg" [key val ...]   # level 2 (default threshold)
zlog::debug "msg" [key val ...]   # level 3

zlog::infof  "Loaded %d items in %.2fs" $count $elapsed   # printf-style
```

### Context loggers

```zsh
zlog::with_context "request_id" "abc-123" "user" "alice"
local ctx="$REPLY"

${ctx}::info  "Request received"          # → ... | request_id=abc-123 user=alice
${ctx}::error "Handler failed" code 500

zlog::remove_context "$ctx"
```

### Control flow

```zsh
zlog::with_level debug my_function      # temporarily raise level
zlog::silent      my_function           # suppress all logging
zlog::once   "startup" info "Init done" # log only on first call
zlog::rate_limit "warn-key" 5 60 warn "Slow query"  # max 5/min
```

### Benchmarking

```zsh
zlog::benchmark "import" load_data file.csv
# → [INFO ] import completed | duration=142ms
```

### Configuration

```zsh
zlog::setup "/var/log/app.log" info text   # quick start
zlog::set_level debug                       # change level at runtime
zlog::set_format json                       # switch to JSON
zlog::set_rotation 1 "50MB" 10             # rotate at 50 MB, keep 10
zlog::enable_buffering 200                  # buffer 200 lines before flush
zlog::show_config                           # print current settings table
zlog::reset                                 # restore all defaults
```

---

## Documentation

| Document                                     | Description                                     |
|----------------------------------------------|-------------------------------------------------|
| [docs/README.md](docs/README.md)             | Full user guide with examples for every feature |
| [docs/api.md](docs/api.md)                   | Complete API reference — every public function  |
| [docs/architecture.md](docs/architecture.md) | Internal architecture with Mermaid diagrams     |

---

## Requirements

- **Zsh 5.8+** (uses `$EPOCHREALTIME`, associative arrays, `zsh/datetime`)
- `stat` — for file rotation size checks (GNU or BSD; auto-detected)
- `mktemp` — for async FIFO (standard on all platforms)

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and PRs are welcome.

---

## License

[MIT](LICENSE)