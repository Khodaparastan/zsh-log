# zlog

> high-performance, feature-rich logging library for Zsh.

`zlog` is a single-file, zero-dependency logging framework that brings the ergonomics of modern structured loggers (like `zerolog` or `zap`) to Zsh scripts. Drop it in, source it, and get leveled logging, file rotation, JSON output, context fields, benchmarking, and async I/O — all without leaving the shell.

---

## Table of Contents

- [Why zlog?](#why-zlog)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Log Levels](#log-levels)
- [Output Formats](#output-formats)
- [Key-Value Fields](#key-value-fields)
- [Writing to a File](#writing-to-a-file)
- [Context Loggers](#context-loggers)
- [Printf-Style Logging](#printf-style-logging)
- [Control-Flow Helpers](#control-flow-helpers)
- [Rate Limiting & Log-Once](#rate-limiting--log-once)
- [Benchmarking](#benchmarking)
- [Buffering](#buffering)
- [Async Logging](#async-logging)
- [Performance Mode](#performance-mode)
- [Configuration Reference](#configuration-reference)
- [Documentation](#documentation)

---

## Why zlog?

Most shell scripts use `echo` for logging. That works until it doesn't — when you need to:

- Filter output by severity at runtime
- Write logs to a file *and* the terminal simultaneously
- Attach structured fields to a message for later parsing
- Rotate log files automatically
- Profile slow sections of a script

`zlog` solves all of these without requiring any external tools or compiled binaries.

```
2026-03-15 14:32:01 [INFO ] (12345) Server started          port=8080 env=production
2026-03-15 14:32:05 [WARN ] (12345) High memory usage       used_mb=1820 limit_mb=2048
2026-03-15 14:32:09 [ERROR] (12345) Connection refused      host=db.internal retries=3
```

---

## Installation

Copy `zlog` into your project and source it:

```zsh
source /path/to/zlog
```

That's it. No package manager, no dependencies, no compilation. The file is self-contained and safe to source multiple times.

**Requirements:** Zsh 5.1+ with the `zsh/datetime` module (standard on macOS and all major Linux distributions).

---

## Quick Start

```zsh
#!/usr/bin/env zsh
source ./zlog

# Console-only logging at INFO level (the default)
zlog::info  "Application started"
zlog::debug "This won't show at INFO level"
zlog::warn  "Disk space is low"
zlog::error "Failed to connect"
```

Output:

```
2026-03-15 14:32:01 [INFO ] (9821) Application started
2026-03-15 14:32:01 [WARN ] (9821) Disk space is low
2026-03-15 14:32:01 [ERROR] (9821) Failed to connect
```

To configure a log file, level, and format in one call:

```zsh
zlog::setup "/var/log/myapp.log" debug json
```

---

## Log Levels

Four levels, in order of severity:

| Level   | Function          | When to use |
|---------|-------------------|-------------|
| `error` | `zlog::error`   | Something broke. Needs immediate attention. |
| `warn`  | `zlog::warn`    | Something unexpected, but recoverable. |
| `info`  | `zlog::info`    | Normal operational events. |
| `debug` | `zlog::debug`   | Detailed diagnostic information. |

The active level acts as a **minimum threshold** — messages below it are silently dropped with zero overhead.

```zsh
zlog::set_level warn    # only warn and error will be logged
zlog::set_level debug   # log everything
zlog::set_level info    # default
```

You can also set **separate levels** for console and file output:

```zsh
zlog::set_level       debug   # console: everything
zlog::set_file_level  error   # file: only errors
```

---

## Output Formats

### Text (default)

Human-readable, color-coded output. Colors are automatically disabled when output is not a TTY or when `NO_COLOR` is set.

```
2026-03-15 14:32:01 [INFO ] (9821) User logged in   user=alice ip=192.168.1.10
```

### JSON

Machine-readable, one object per line. Ideal for log aggregators (Datadog, Loki, Splunk).

```zsh
zlog::set_format json
```

```json
{"timestamp":"2026-03-15T14:32:01Z","level":"INFO","message":"User logged in","pid":9821,"hostname":"web-01","user":"alice","ip":"192.168.1.10"}
```

Switch formats at any time — even mid-script.

---

## Key-Value Fields

Append structured fields to any log message as trailing `key value` pairs:

```zsh
zlog::info "Request completed" \
    method  GET \
    path    /api/users \
    status  200 \
    latency 42ms
```

Text output:
```
2026-03-15 14:32:01 [INFO ] (9821) Request completed   method=GET path=/api/users status=200 latency=42ms
```

JSON output:
```json
{"timestamp":"...","level":"INFO","message":"Request completed","method":"GET","path":"/api/users","status":"200","latency":"42ms"}
```

Fields are always the last arguments. Any even number of trailing args after the message are treated as key-value pairs.

---

## Writing to a File

```zsh
zlog::set_file "/var/log/myapp.log"
```

From this point, every log message goes to **both** the console and the file. The file always receives plain text (no ANSI color codes), regardless of the console format.

### Automatic Rotation

```zsh
# Rotate at 50 MB, keep 7 old files
zlog::set_rotation 1 "50MB" 7
```

Rotation is multi-process safe (uses a lock file). Supported size units: `KB`, `MB`, `GB`.

---

## Context Loggers

A context logger is a namespaced logger that automatically appends a fixed set of fields to every message. Perfect for request-scoped or session-scoped logging.

```zsh
# Create a context logger with fixed fields
zlog::with_context "request_id" "req-abc123" "user" "alice"
local ctx="$REPLY"

# Use it exactly like the global logger
${ctx}::info  "Processing request"
${ctx}::debug "Cache miss"          key "/users/alice"
${ctx}::warn  "Slow query"          duration_ms 320
${ctx}::error "Payment failed"      code 402

# Clean up when done
zlog::remove_context "$ctx"
```

Every message from this context automatically includes `request_id=req-abc123 user=alice` — you never have to repeat those fields.

---

## Printf-Style Logging

For dynamic messages with formatting, use the `f`-suffixed variants:

```zsh
zlog::infof  "Processed %d records in %.2f seconds" $count $elapsed
zlog::debugf "Cache hit ratio: %.1f%%" $ratio
zlog::warnf  "Retry %d/%d for host %s" $attempt $max_retries $host
zlog::errorf "Exit code %d from command: %s" $rc "$cmd"
```

These accept the same format strings as `printf`.

---

## Control-Flow Helpers

### Temporarily change the log level

```zsh
zlog::with_level debug my_verbose_function arg1 arg2
# Level is restored automatically after the function returns
```

### Silence all logging for a block

```zsh
zlog::silent noisy_third_party_function
```

### Force a message through regardless of level

```zsh
zlog::always "Startup complete — version $VERSION"
```

---

## Rate Limiting & Log-Once

Prevent log flooding in hot loops:

```zsh
# Log at most 5 times per 60 seconds for this key
while true; do
    zlog::rate_limit "health_check" 5 60 warn "Service degraded" host "$target"
    sleep 1
done
```

Log a message exactly once per script run:

```zsh
for item in "${items[@]}"; do
    zlog::once "deprecation_notice" warn "Flag --legacy is deprecated"
    process "$item"
done
# The warning appears only on the first iteration
```

---

## Benchmarking

### Wrap a command

```zsh
zlog::benchmark "database_seed" run_migrations --env production
# Logs: [INFO] database_seed completed  duration=1.23s
```

### Manual start/stop

```zsh
zlog::benchmark_start "image_resize"
local timer="$REPLY"

convert input.png -resize 800x600 output.png

zlog::benchmark_end "$timer"
```

### Inline block

```zsh
zlog::benchmark_block "data_processing" <<'END'
    for file in /data/*.csv; do
        process_csv "$file"
    done
END
```

Durations are formatted automatically: `µs`, `ms`, `s`, or `Xm Y.YYs`. Benchmarking is a **no-op** when INFO level is disabled — no overhead in production.

---

## Buffering

Batch file writes for high-throughput scenarios:

```zsh
zlog::enable_buffering 200   # buffer up to 200 messages

for i in {1..10000}; do
    zlog::debug "Processing item $i"
done

zlog::flush   # write all buffered messages at once
```

The buffer is flushed automatically on `ERROR` messages and on script exit (via `zshexit` hook).

---

## Async Logging

Offload file I/O to a background worker to keep the main script fast:

```zsh
zlog::enable_async

# Your script continues immediately; log writes happen in the background
zlog::info "This returns instantly"

zlog::disable_async   # graceful shutdown, waits up to 5s for the worker to finish
```

> **Note:** Async logging is experimental. Avoid it in scripts that may be killed abruptly.

---

## Performance Mode

For scripts that log millions of messages, swap in the fast engine at runtime:

```zsh
zlog::enable_performance_mode

# Hot inner loop — uses the fast engine (~50µs vs ~150µs per message)
for i in {1..1000000}; do
    zlog::debug "tick $i"
done

zlog::disable_performance_mode
```

The fast engine skips recursion guards, level re-validation, and error handling. Use it only in controlled, high-throughput sections.

---

## Configuration Reference

### One-call setup

```zsh
zlog::setup <file> [level] [format]

zlog::setup "-"                    # console only, INFO, text
zlog::setup "/var/log/app.log"     # file + console, INFO, text
zlog::setup "/var/log/app.log" debug json
```

### Individual setters

```zsh
zlog::set_level        <level>          # error | warn | info | debug
zlog::set_file         <path>           # enable file output
zlog::set_file_level   <level>          # independent level for file
zlog::set_format       <text|json>      # output format
zlog::set_rotation     <1|0> <size> <keep>   # e.g. 1 "10MB" 5
zlog::set_timestamp_format <strftime>   # e.g. "%H:%M:%S"
zlog::enable_buffering [size]           # enable write buffering
zlog::enable_async                      # enable async file I/O
zlog::enable_performance_mode           # swap in fast engine
```

### Inspect & reset

```zsh
zlog::show_config    # pretty-print all current settings
zlog::get_stats      # messages logged, dropped, rotations, errors
zlog::reset          # restore all defaults
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [API Reference](./api.md) | Complete reference for all 83 public functions with signatures, parameters, and examples |
| [Architecture](./architecture.md) | Internal design, data flow diagrams, and Mermaid charts covering all 20 subsystems |

---

## License

MIT
