# zlog Architecture

> **zlog** is a 6 000+ line, self-contained structured logging framework for Zsh.  
> It is designed to be sourced once and provides a full production-grade logging system with levels, file rotation, buffering, async I/O, context loggers, rate limiting, benchmarking, and color output — all with zero external dependencies beyond a standard Zsh 5.3+ installation.

---

## Table of Contents

1. [High-Level Overview](#1-high-level-overview)
2. [Module Map](#2-module-map)
3. [Global State Model](#3-global-state-model)
4. [Initialization Sequence](#4-initialization-sequence)
5. [Log Level System](#5-log-level-system)
6. [Core Engine](#6-core-engine)
7. [Formatter Pipeline](#7-formatter-pipeline)
8. [Color System](#8-color-system)
9. [Timestamp System](#9-timestamp-system)
10. [File I/O & Rotation](#10-file-io--rotation)
11. [Buffering System](#11-buffering-system)
12. [Async Logging](#12-async-logging)
13. [Context Logging](#13-context-logging)
14. [Benchmarking System](#14-benchmarking-system)
15. [Rate Limiting & Once Logging](#15-rate-limiting--once-logging)
16. [Control-Flow Helpers](#16-control-flow-helpers)
17. [Configuration Management](#17-configuration-management)
18. [Cleanup & Resource Management](#18-cleanup--resource-management)
19. [Performance Mode](#19-performance-mode)
20. [Public API Reference](#20-public-api-reference)
21. [Data Flow: End-to-End](#21-data-flow-end-to-end)
22. [Naming Conventions](#22-naming-conventions)
23. [Design Principles](#23-design-principles)

---

## 1. High-Level Overview

```mermaid
graph TD
    User["User / Script"]

    subgraph Public_API["Public API  (zlog::*)"]
        Core["Core\nerror / warn / info / debug"]
        Printf["Printf-style\nerrorf / warnf / infof / debugf"]
        Control["Control-flow\nwith_level / silent / once / rate_limit"]
        Ctx["Context Loggers\nwith_context / remove_context"]
        Bench["Benchmarking\nbenchmark / benchmark_start / benchmark_end"]
        Cfg["Configuration\nsetup / set_level / set_format / reset"]
    end

    subgraph Engine["Core Engine  (__zlog::engine)"]
        Guard["Recursion Guard"]
        LevelCheck["Level Filter"]
        Format["Formatter Pipeline"]
        Output["Output Router"]
    end

    subgraph Output_Targets["Output Targets"]
        Console["Console (stderr)"]
        Buffer["In-Memory Buffer"]
        File["Log File"]
        Async["Async FIFO Worker"]
    end

    subgraph Support["Support Systems"]
        Colors["Color System"]
        Timestamps["Timestamp Cache"]
        Rotation["File Rotation"]
        Stats["Statistics"]
    end

    User --> Public_API
    Public_API --> Engine
    Engine --> Output_Targets
    Engine --> Support
    Buffer -->|flush| File
    Async -->|FIFO| File
```

---

## 2. Module Map

The file is organized into 20 sequential sections. Each section is self-contained and depends only on sections above it.

```mermaid
graph LR
    S1["① Constants\n& Guards"]
    S2["② Global State\nDeclaration"]
    S3["③ Init &\nValidation"]
    S4["④ Color\nSystem"]
    S5["⑤ Utility\nHelpers"]
    S6["⑥ Timestamp\nSystem"]
    S7["⑦ File Mgmt\n& Rotation"]
    S8["⑧ Buffering\nSystem"]
    S9["⑨ Formatters"]
    S10["⑩ Core\nEngine"]
    S11["⑪ Public API\nCore"]
    S12["⑫ Printf\nAPI"]
    S13["⑬ Control-flow\nHelpers"]
    S14["⑭ Context\nLogging"]
    S15["⑮ Benchmarking"]
    S16["⑯ Cleanup &\nResources"]
    S17["⑰ Config\nManagement"]
    S18["⑱ Async\nLogging"]
    S19["⑲ Performance\nMode"]
    S20["⑳ Bootstrap"]

    S1 --> S2 --> S3 --> S4 --> S5 --> S6 --> S7 --> S8 --> S9 --> S10
    S10 --> S11 --> S12 --> S13 --> S14 --> S15 --> S16 --> S17 --> S18 --> S19 --> S20
```

---

## 3. Global State Model

All global variables are declared with `if (( ! ${+var} ))` guards, making the file **safely re-sourceable** without resetting live state.

```mermaid
classDiagram
    class _zlog_config {
        +int level = 2
        +int file_level = -1
        +string format = "text"
        +string file = ""
        +int rotate = 1
        +int rotate_size = 10485760
        +int rotate_keep = 5
        +int rotation_lock_timeout = 5
        +int buffered = 0
        +int buffer_max = 50
        +int fast_mode = 0
        +int max_message_size = 0
        +string truncate_marker
        +int timestamp_cache_enabled = 1
        +int debug_mode = 0
        +string exit_hook_method
    }

    class _zlog_state {
        +int fd = -1
        +string stat_cmd
        +string async_pid
        +int async_fd = -1
        +string async_fifo
        +int depth = 0
        +int buffer_count = 0
        +int cleanup_registered = 0
        +int console_enabled = 1
        +int file_enabled = 0
        +int any_logging_enabled = 1
        +int context_count = 0
        +int timer_count = 0
    }

    class _zlog_stats {
        +int messages_logged = 0
        +int messages_dropped = 0
        +int rotations_performed = 0
        +int buffer_flushes = 0
        +int errors_encountered = 0
    }

    class _zlog_timestamp_cache {
        +int epoch = 0
        +string formatted
        +string iso
        +string ms
        +string custom_format
    }

    class _zlog_sys_cache {
        +string hostname
        +string username
        +string pid
    }

    class _zlog_colors {
        +string reset, bold, dim
        +string error, warn, info, debug
        +string red, green, yellow, cyan ...
    }

    class _zlog_buffer {
        <<array>>
        +string[] lines
    }

    class _zlog_contexts {
        <<assoc array>>
        +string ctx_id → "key\0val\0key\0val"
    }

    class _zlog_benchmark_timers {
        <<assoc array>>
        +string timer_id → "start_epoch|name"
    }

    class _zlog_rate_limits {
        <<assoc array>>
        +string key → "count|window_start"
    }

    class _zlog_once_keys {
        <<assoc array>>
        +string key → 1
    }

    _zlog_config --> _zlog_state : drives fast-path flags
    _zlog_state --> _zlog_stats : updated on every write
    _zlog_timestamp_cache --> _zlog_config : cache_enabled flag
```

### Fast-Path Flags

`__zlog::update_fast_flags` pre-computes three booleans into `_zlog_state` so every public log call can do a single integer check as its very first operation:

| Flag | Formula |
|---|---|
| `console_enabled` | `_zlog_config[level] >= 0` |
| `file_enabled` | `${#_zlog_config[file]} > 0` |
| `any_logging_enabled` | `console_enabled OR file_enabled` |

---

## 4. Initialization Sequence

```mermaid
sequenceDiagram
    participant Shell as Zsh Shell
    participant File as zlog (source)
    participant Globals as Global State
    participant Colors as Color System
    participant TS as Timestamp Cache
    participant Sys as Sys Cache

    Shell->>File: source zlog
    File->>Globals: Declare constants (readonly)
    File->>Globals: Declare _zlog_config (if not set)
    File->>Globals: Declare _zlog_state, _zlog_stats, caches
    File->>File: __zlog::init_globals()
    File->>Sys: Cache hostname, username, PID
    File->>File: Detect stat command (gnu/bsd/none)
    File->>File: Check strftime availability
    File->>File: __zlog::update_fast_flags()
    File->>File: __zlog::validate_globals()
    Note over File: Clamp all config values to valid ranges
    File->>Colors: __zlog::init_colors()
    Colors->>Colors: detect_color_support() → none/basic/256/truecolor
    Colors->>Colors: Populate _zlog_colors[] with ANSI codes
    File->>TS: __zlog::update_timestamp()
    TS->>TS: Prime epoch/formatted/iso/ms cache
    File->>Sys: Cache hostname from $HOST/$HOSTNAME
    File->>Sys: Cache username from $USER/$USERNAME
    File-->>Shell: Ready (idempotent, safe to re-source)
```

---

## 5. Log Level System

```mermaid
graph LR
    subgraph Levels["Log Levels (numeric)"]
        E["0 = ERROR\n🔴 Always critical"]
        W["1 = WARN\n🟡 Warnings"]
        I["2 = INFO\n🔵 Default level"]
        D["3 = DEBUG\n⚪ Verbose"]
    end

    subgraph Lookup["Lookup Tables (readonly assoc arrays)"]
        Names["_ZLOG_LEVEL_NAMES\n0→ERROR, 1→WARN\n2→INFO, 3→DEBUG"]
        Values["_ZLOG_LEVEL_VALUES\nERROR→0, error→0\nWARN→1, warn→1\n..."]
    end

    subgraph Filter["Level Filtering Logic"]
        CL["console_level\n(_zlog_config[level])"]
        FL["file_level\n(_zlog_config[file_level])\n-1 = follow console"]
        SC["should_console\nlevel <= console_level"]
        SF["should_file\nfile_enabled AND level <= file_level"]
    end

    E & W & I & D --> Names
    Names --> Values
    CL --> SC
    FL --> SF
```

**File level special value:** `-1` (or `"console"`) means the file always follows the console level. This is the default.

---

## 6. Core Engine

The engine is the single central function that all public log calls delegate to. It is the only place where output decisions are made.

```mermaid
flowchart TD
    Start([__zlog::engine\nlevel, message, kv...])

    RG{"depth >= max_depth?"}
    RG_ERR["print recursion error\nreturn 1"]
    INC["depth++"]

    VL{"level valid?\n0-3 numeric"}
    VL_ERR["print error\nrestore depth\nreturn 2"]

    FP{"any_logging_enabled?"}
    FP_EXIT["restore depth\nreturn 0"]

    CALC["Compute:\nshould_console = level <= console_level\nshould_file = file_enabled AND level <= file_level"]

    BOTH{"should_console\nOR should_file?"}
    BOTH_EXIT["restore depth\nreturn 0"]

    FMT["__zlog::format()\nlevel, message, kv pairs"]
    FMT_ERR{"format failed?"}
    FALLBACK["Fallback: date + level + message"]

    STATS["_zlog_stats[messages_logged]++"]

    CON{"should_console?"}
    CON_OUT["print -u2 formatted\n(stderr)"]
    CON_FAIL["stats[errors_encountered]++"]

    FILE{"should_file?"}
    BUF{"buffered mode?"}
    BUF_ADD["__zlog::buffer_add()"]
    WRITE["__zlog::write_file()"]
    WRITE_FAIL["log error (max 5 times)"]

    RESTORE["restore depth"]
    End([return 0])

    Start --> RG
    RG -->|yes| RG_ERR
    RG -->|no| INC --> VL
    VL -->|invalid| VL_ERR
    VL -->|valid| FP
    FP -->|no| FP_EXIT
    FP -->|yes| CALC --> BOTH
    BOTH -->|neither| BOTH_EXIT
    BOTH -->|at least one| FMT
    FMT --> FMT_ERR
    FMT_ERR -->|yes| FALLBACK
    FMT_ERR -->|no| STATS
    FALLBACK --> STATS
    STATS --> CON
    CON -->|yes| CON_OUT --> CON_FAIL
    CON -->|no| FILE
    CON_FAIL --> FILE
    FILE -->|yes| BUF
    BUF -->|yes| BUF_ADD
    BUF -->|no| WRITE
    BUF_ADD --> WRITE_FAIL
    WRITE --> WRITE_FAIL
    WRITE_FAIL --> RESTORE
    FILE -->|no| RESTORE
    RESTORE --> End
```

### Engine Variants

| Variant | Function | Speed | Safety |
|---|---|---|---|
| Normal | `__zlog::engine` | ~100–200µs | Full recursion guard, validation, error handling |
| Fast | `__zlog::engine_fast` | ~50–80µs | No recursion guard, no validation, no error handling |

Performance mode hot-swaps the engine at runtime by copying function bodies:
```zsh
functions[__zlog::engine_original]="${functions[__zlog::engine]}"
functions[__zlog::engine]="${functions[__zlog::engine_fast]}"
```

---

## 7. Formatter Pipeline

```mermaid
flowchart TD
    Engine["__zlog::engine\nlevel, message, kv..."]

    HasKV{"KV pairs\nprovided?"}
    Simple["__zlog::format_simple\n(fast path, sets REPLY)"]
    Full["__zlog::format\n(full path)"]

    FmtCheck{"_zlog_config[format]"}
    Text["__zlog::format_text"]
    JSON["__zlog::format_json"]

    TTY{"stderr is TTY?"}
    Plain["Plain text\nno ANSI codes"]
    Colored["Colored text\nANSI escape codes"]

    JSONEsc["__z::json::escape\neach value"]
    JSONOut["JSON object string\nwith all fields"]

    REPLY["REPLY = formatted string"]

    Engine --> HasKV
    HasKV -->|no KV| Simple
    HasKV -->|has KV| Full
    Simple --> FmtCheck
    Full --> FmtCheck
    FmtCheck -->|text| Text
    FmtCheck -->|json| JSON
    Text --> TTY
    TTY -->|no| Plain --> REPLY
    TTY -->|yes| Colored --> REPLY
    JSON --> JSONEsc --> JSONOut --> REPLY
```

### Text Format Output

```
2026-03-15 14:23:01 [INFO ] (1234) Message text | key=value key2=value2
│─────────────────│ │─────│ │────│ │───────────│   │──────────────────│
  dim timestamp     bold    dim    message text      context KV pairs
                   colored  PID                      key=dim, val=cyan
```

Level names are right-padded to 5 characters for column alignment (`INFO `, `WARN `, `ERROR`, `DEBUG`).

### JSON Format Output

```json
{
  "timestamp": "2026-03-15T14:23:01Z",
  "level":     "INFO",
  "message":   "Message text",
  "hostname":  "myhost",
  "pid":       1234,
  "user":      "alice",
  "key":       "value",
  "key2":      "value2"
}
```

Reserved JSON field names (`timestamp`, `level`, `message`, `hostname`, `pid`, `user`) are **rejected** as context keys. Invalid characters are stripped by `__zlog::sanitize_context_key`.

---

## 8. Color System

```mermaid
flowchart TD
    Init["__zlog::init_colors()"]

    NoColor{"NO_COLOR\nenv set?"}
    NoColorOut["mode = none\nAll codes = empty string"]

    TTYCheck{"stderr is\na TTY?"}
    NoneOut["mode = none"]

    TermCheck{"TERM == dumb?"}

    TrueColor{"COLORTERM ==\ntruecolor or 24bit?"}
    TC["mode = truecolor\nUse ESC[38;2;R;G;Bm"]

    Term256{"TERM contains\n256?"}
    C256["mode = 256\nUse ESC[38;5;Nm\nRGB→256 via rgb_to_256()"]

    TputCheck{"tput colors\n>= 256?"}
    Basic["mode = basic\nUse ESC[3Xm codes"]

    TermFallback{"TERM matches\nxterm/screen/tmux...?"}
    BasicFB["mode = basic"]
    NoneFF["mode = none"]

    Init --> NoColor
    NoColor -->|yes| NoColorOut
    NoColor -->|no| TTYCheck
    TTYCheck -->|no| NoneOut
    TTYCheck -->|yes| TermCheck
    TermCheck -->|yes| NoneOut
    TermCheck -->|no| TrueColor
    TrueColor -->|yes| TC
    TrueColor -->|no| Term256
    Term256 -->|yes| C256
    Term256 -->|no| TputCheck
    TputCheck -->|yes| C256
    TputCheck -->|no| TermFallback
    TermFallback -->|yes| BasicFB
    TermFallback -->|no| NoneFF
```

### Color Slots

| Slot | Purpose |
|---|---|
| `reset`, `bold`, `dim`, `underline` | Text attributes |
| `error`, `warn`, `info`, `debug`, `success` | Semantic level colors |
| `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white` | Named colors |
| `bright_*` | Bright variants |
| `bg_*` | Background variants |

In truecolor/256 mode, colors are defined as specific RGB values (e.g., red = `205,49,49`) for visual consistency across terminals.

---

## 9. Timestamp System

```mermaid
flowchart TD
    Call["Any log call"]
    Epoch["Read EPOCHSECONDS\n(zsh/datetime)"]
    Cache{"epoch ==\ncache[epoch]?"}
    Return["Use cached values\nformatted / iso / ms"]

    Update["__zlog::update_timestamp()"]
    Strftime{"strftime\navailable?"}
    SF["strftime '%Y-%m-%d %H:%M:%S'\n→ cache[formatted]"]
    Date["date '+%Y-%m-%d %H:%M:%S'\n→ cache[formatted]"]

    ISO["Build ISO 8601\n→ cache[iso]"]
    MS["EPOCHREALTIME * 1000\n→ cache[ms]"]
    Store["Store epoch\n→ cache[epoch]"]

    Call --> Epoch --> Cache
    Cache -->|hit| Return
    Cache -->|miss| Update
    Update --> Strftime
    Strftime -->|yes| SF
    Strftime -->|no| Date
    SF --> ISO --> MS --> Store --> Return
```

**Cache key:** `EPOCHSECONDS` (integer seconds). Within the same second, all log calls share the same formatted timestamp — zero repeated `strftime` calls.

**Available timestamp formats:**

| Key | Example | Use |
|---|---|---|
| `formatted` | `2026-03-15 14:23:01` | Human-readable (default) |
| `iso` | `2026-03-15T14:23:01Z` | JSON output |
| `ms` | `1705329781234` | Millisecond epoch |
| `epoch` | `1705329781` | Integer epoch |

Custom format: `zlog::set_timestamp_format "%H:%M:%S"` — validated with a test `strftime` call before accepting.

---

## 10. File I/O & Rotation

```mermaid
flowchart TD
    Write["__zlog::write_file(message)"]

    RotateCheck{"rotate=1 AND\nfile exists?"}
    SizeCheck["__zlog::get_file_size()\nstat (gnu/bsd/none)"]
    SizeOver{"size >=\nrotate_size?"}

    Lock["Acquire lock file\nlogfile.lock\n(timeout: rotation_lock_timeout)"]
    LockFail["Log warning\nSkip rotation\nWrite anyway"]

    Rotate["__zlog::rotate_file()"]
    Shift["Shift: .log.4→.log.5\n.log.3→.log.4 ...\n.log→.log.1"]
    Prune["Delete files beyond\nrotate_keep count"]
    Unlock["Release lock file"]

    Append["print -r -- message >> logfile"]
    AsyncCheck{"async_fd\nset?"}
    AsyncWrite["print -u async_fd message"]

    Write --> RotateCheck
    RotateCheck -->|no| AsyncCheck
    RotateCheck -->|yes| SizeCheck
    SizeCheck --> SizeOver
    SizeOver -->|no| AsyncCheck
    SizeOver -->|yes| Lock
    Lock -->|failed| LockFail --> AsyncCheck
    Lock -->|acquired| Rotate
    Rotate --> Shift --> Prune --> Unlock --> AsyncCheck
    AsyncCheck -->|yes| AsyncWrite
    AsyncCheck -->|no| Append
```

### `stat` Command Detection

On init, zlog auto-detects which `stat` variant is available:

| Priority | Command | Flag |
|---|---|---|
| 1 | `gstat` (GNU coreutils on macOS) | `-c%s` |
| 2 | `stat -f%z` | BSD (macOS native) |
| 3 | `stat -c%s` | GNU (Linux) |
| 4 | none | Rotation disabled |

### Rotation Naming

```
app.log          ← current (always written here)
app.log.1        ← most recent backup
app.log.2
...
app.log.N        ← oldest (N = rotate_keep, default 5)
```

Files beyond `rotate_keep` are deleted. The lock file (`app.log.lock`) prevents concurrent rotation from multiple processes.

---

## 11. Buffering System

```mermaid
stateDiagram-v2
    [*] --> Unbuffered : default

    Unbuffered --> Buffered : zlog::enable_buffering [size]
    Buffered --> Unbuffered : zlog::disable_buffering

    state Buffered {
        [*] --> Accumulating
        Accumulating --> AutoFlush : level==ERROR OR count>=buffer_max
        Accumulating --> ManualFlush : zlog::flush
        Accumulating --> ExitFlush : process exit / signal
        AutoFlush --> Accumulating : buffer cleared
        ManualFlush --> Accumulating : buffer cleared
        ExitFlush --> [*]
    }
```

**Flush mechanism:** A single `printf '%s\n' "${_zlog_buffer[@]}"` bulk write — far more efficient than per-line `>>` appends.

**Exit hook registration** (tries in order, uses first that works):
1. `add-zsh-hook zshexit` (preferred, Zsh native)
2. `TRAPEXIT` function
3. `trap ... EXIT`

All three also register `INT TERM HUP QUIT` signal handlers to flush on abnormal termination.

---

## 12. Async Logging

```mermaid
sequenceDiagram
    participant Script
    participant zlog
    participant FIFO as Named FIFO\n/tmp/zlog_fifo_PID_RAND
    participant Worker as Background Worker\n(subshell)
    participant LogFile as Log File

    Script->>zlog: zlog::enable_async()
    zlog->>FIFO: mkfifo /tmp/zlog_fifo_$$_RANDOM
    zlog->>Worker: spawn background subshell
    Worker->>FIFO: exec < fifo (open for reading)
    zlog->>FIFO: exec {fd}> fifo (open for writing)
    zlog->>zlog: store async_pid, async_fd

    loop Every log message
        Script->>zlog: zlog::info "msg"
        zlog->>FIFO: print -u async_fd "formatted line"
        FIFO->>Worker: line available
        Worker->>LogFile: print -r -- line >> logfile
    end

    Script->>zlog: zlog::disable_async()
    zlog->>FIFO: print "__ASYNC_SHUTDOWN__"
    Worker->>Worker: break on sentinel
    Worker->>FIFO: rm -f fifo
    zlog->>zlog: wait up to 5s for worker
    zlog->>zlog: clear async_pid/fd/fifo
```

> **Note:** Async logging is marked experimental. It adds throughput for high-volume file logging but introduces complexity (FIFO lifecycle, worker crash handling).

---

## 13. Context Logging

Context loggers attach a fixed set of key-value pairs to every log call, without repeating them at each call site.

```mermaid
flowchart TD
    Create["zlog::with_context\n'request_id' 'abc' 'user' 'john'"]
    ID["Generate ID:\nzlog_ctx_PID_EPOCHSECONDS_RANDOM"]
    Store["_zlog_contexts[id] = 'request_id\0abc\0user\0john'"]
    Order["_zlog_contexts_order += id"]
    Limit{"context_count\n> MAX_CONTEXTS (100)?"}
    Evict["Remove oldest context\n(LRU eviction)"]
    GenFuncs["eval: create 8 functions\nid::error / errorf\nid::warn / warnf\nid::info / infof\nid::debug / debugf"]
    REPLY["REPLY = id"]

    Use["${ctx}::info 'User action'"]
    Lookup["Load KV pairs from\n_zlog_contexts[ctx]"]
    Merge["Merge with call-site KV pairs"]
    Engine["__zlog::engine\nlevel, message, merged KV..."]

    Remove["zlog::remove_context ctx"]
    Unset["unfunction ctx::*\nunset _zlog_contexts[ctx]"]

    Create --> ID --> Store --> Order --> Limit
    Limit -->|yes| Evict --> GenFuncs
    Limit -->|no| GenFuncs
    GenFuncs --> REPLY

    Use --> Lookup --> Merge --> Engine
    Remove --> Unset
```

### Context Storage Format

Context KV pairs are stored as a null-byte (`\0`) separated string:
```
"request_id\0abc123\0user\0john\0session\0xyz"
```
This avoids nested arrays and is split at call time with `${(s:\0:)ctx_string}`.

---

## 14. Benchmarking System

```mermaid
flowchart TD
    subgraph Wrap["Wrap Mode"]
        BW["zlog::benchmark 'name' cmd args"]
        BWS["Record start time\n(EPOCHREALTIME)"]
        BWR["Run cmd args"]
        BWE["Record end time\nCompute duration"]
        BWL["zlog::info 'name completed'\n'duration' '42.3ms'"]
        BW --> BWS --> BWR --> BWE --> BWL
    end

    subgraph Manual["Manual Mode"]
        BS["zlog::benchmark_start 'name'"]
        BSS["timer_id = zbt_PID_EPOCH_RANDOM\n_zlog_benchmark_timers[id] = 'epoch|name'"]
        BSR["REPLY = timer_id"]
        BE["zlog::benchmark_end timer_id"]
        BEL["Lookup start time\nCompute duration\nzlog::info 'name' 'duration' '...'"]
        BS --> BSS --> BSR
        BE --> BEL
    end

    subgraph Block["Block Mode"]
        BB["zlog::benchmark_block 'name' <<'END'\n  code\nEND"]
        BBE["eval code in subshell\ntime with EPOCHREALTIME"]
        BBL["zlog::info 'name' 'duration' '...'"]
        BB --> BBE --> BBL
    end
```

**Duration formatting:**

| Range | Format | Example |
|---|---|---|
| < 1ms | microseconds | `842µs` |
| < 1s | milliseconds | `42.3ms` |
| < 60s | seconds | `3.14s` |
| ≥ 60s | minutes + seconds | `2m 5.30s` |

All benchmark functions are **no-ops** when the INFO level is disabled — zero overhead in production.

---

## 15. Rate Limiting & Once Logging

```mermaid
flowchart TD
    subgraph RateLimit["Rate Limiting"]
        RL["zlog::rate_limit\n'key' max_count window_secs level 'msg'"]
        RLLoad["Load state:\n_zlog_rate_limits[key]\n= 'count|window_start'"]
        RLWindow{"Current time\n> window_start + window?"}
        RLReset["Reset: count=0\nwindow_start=now"]
        RLCheck{"count < max?"}
        RLInc["count++\nLog the message"]
        RLDrop["Drop: _zlog_stats[messages_dropped]++"]
        RL --> RLLoad --> RLWindow
        RLWindow -->|yes| RLReset --> RLCheck
        RLWindow -->|no| RLCheck
        RLCheck -->|yes| RLInc
        RLCheck -->|no| RLDrop
    end

    subgraph Once["Once Logging"]
        OL["zlog::once 'key' level 'msg'"]
        OLCheck{"_zlog_once_keys[key]\nexists?"}
        OLLog["Log the message\n_zlog_once_keys[key]=1"]
        OLSkip["Skip silently"]
        OL --> OLCheck
        OLCheck -->|no| OLLog
        OLCheck -->|yes| OLSkip
    end
```

---

## 16. Control-Flow Helpers

```mermaid
flowchart LR
    subgraph WithLevel["zlog::with_level level cmd"]
        WL1["Save current level"]
        WL2["Set level to arg"]
        WL3["Run cmd"]
        WL4["Restore level"]
        WL1 --> WL2 --> WL3 --> WL4
    end

    subgraph Silent["zlog::silent cmd"]
        SL1["Save level"]
        SL2["Set level = -1\n(nothing passes filter)"]
        SL3["Run cmd"]
        SL4["Restore level"]
        SL1 --> SL2 --> SL3 --> SL4
    end

    subgraph Always["zlog::always 'msg'"]
        AL1["Save level"]
        AL2["Set level = DEBUG (3)"]
        AL3["Log at DEBUG\n(passes all filters)"]
        AL4["Restore level"]
        AL1 --> AL2 --> AL3 --> AL4
    end
```

All three helpers save and restore `_zlog_config[level]` around the wrapped call, making them safe for nested use.

---

## 17. Configuration Management

```mermaid
flowchart TD
    subgraph QuickStart["Quick Start"]
        Setup["zlog::setup file level format"]
        Setup --> SF["set_file()"]
        Setup --> SL["set_level()"]
        Setup --> SFmt["set_format()"]
    end

    subgraph Individual["Individual Setters"]
        SL2["zlog::set_level\nerror/warn/info/debug or 0-3"]
        SFL["zlog::set_file_level\nlevel or -1/console"]
        SFile["zlog::set_file\npath or empty"]
        SFmt2["zlog::set_format\ntext or json"]
        SRot["zlog::set_rotation\nenabled max_size keep_count"]
        SBuf["zlog::set_buffer_size\nsize"]
        STS["zlog::set_timestamp_format\nstrftime pattern"]
    end

    subgraph Validation["Input Validation"]
        LV["__zlog::level_number()\nname or number → 0-3"]
        SV["__zlog::parse_size()\n'10MB' → 10485760 bytes"]
        FV["Test strftime call\nbefore accepting format"]
    end

    subgraph Output["Inspection"]
        Show["zlog::show_config()\nBox-drawing table of all settings"]
        Stats["zlog::show_stats()\nMessages logged, dropped, etc."]
    end

    subgraph Reset["Reset"]
        Rst["zlog::reset()\nFlush buffer\nRestore all defaults\nClear caches"]
    end

    Individual --> Validation
    QuickStart --> Validation
    Validation --> Output
```

### Size Parsing (`__zlog::parse_size`)

Accepts human-readable sizes and converts to bytes:

| Input | Bytes |
|---|---|
| `1024` | 1 024 |
| `10KB` | 10 240 |
| `10MB` | 10 485 760 |
| `1GB` | 1 073 741 824 |
| `500TB` | 549 755 813 888 000 |

---

## 18. Cleanup & Resource Management

```mermaid
flowchart TD
    Enable["zlog::enable_buffering"]
    Register{"cleanup_registered\n== 0?"}
    Hook1["add-zsh-hook zshexit\n__zlog::cleanup"]
    Hook2["TRAPEXIT function\n(fallback)"]
    Hook3["trap EXIT INT TERM HUP QUIT\n(last resort)"]
    Mark["cleanup_registered = 1"]

    Signal["Process receives\nEXIT / INT / TERM / HUP / QUIT"]
    Cleanup["__zlog::cleanup()"]
    Flush["zlog::flush()\nWrite all buffered lines"]
    AsyncStop["zlog::disable_async()\nif async active"]
    CtxClean["Remove all context functions\nunfunction ctx::*"]
    Done["Exit"]

    Enable --> Register
    Register -->|yes| Hook1
    Hook1 -->|fails| Hook2
    Hook2 -->|fails| Hook3
    Hook1 & Hook2 & Hook3 --> Mark

    Signal --> Cleanup
    Cleanup --> Flush --> AsyncStop --> CtxClean --> Done
```

---

## 19. Performance Mode

```mermaid
flowchart LR
    Normal["Normal Mode\n__zlog::engine\n~100-200µs/call"]

    Enable["zlog::enable_performance_mode()"]
    Swap["functions[engine_original] = functions[engine]\nfunctions[engine] = functions[engine_fast]"]
    Fast["Performance Mode\n__zlog::engine_fast\n~50-80µs/call"]

    Disable["zlog::disable_performance_mode()"]
    Restore["functions[engine] = functions[engine_original]\nunfunction engine_original"]

    Normal -->|enable| Enable --> Swap --> Fast
    Fast -->|disable| Disable --> Restore --> Normal
```

**What the fast engine skips:**

| Check | Normal Engine | Fast Engine |
|---|---|---|
| Recursion depth guard | ✅ | ❌ |
| Level range validation | ✅ | ❌ |
| Format error handling | ✅ | ❌ |
| Fallback formatting | ✅ | ❌ |
| Statistics tracking | ✅ | ❌ |
| `format_simple` for no-KV | ✅ | ✅ |
| Buffer auto-flush on ERROR | ✅ | ✅ |

---

## 20. Public API Reference

### Naming Convention

```
zlog::<verb>          Public API  (user-facing)
__zlog::<verb>        Private     (internal, do not call directly)
```

### Core Logging

```zsh
zlog::error  "message" [key val ...]
zlog::warn   "message" [key val ...]
zlog::info   "message" [key val ...]
zlog::debug  "message" [key val ...]
zlog::log    "level" "message" [key val ...]   # level by name or number
```

### Printf-style

```zsh
zlog::errorf "format %s %d" arg1 arg2
zlog::warnf  "format %s %d" arg1 arg2
zlog::infof  "format %s %d" arg1 arg2
zlog::debugf "format %s %d" arg1 arg2
```

### Control Flow

```zsh
zlog::with_level  debug  my_function [args]
zlog::silent             my_function [args]
zlog::always      "Critical message"
zlog::once        "unique-key"  info  "message"
zlog::rate_limit  "key"  max_count  window_secs  level  "message"
```

### Context Loggers

```zsh
zlog::with_context "key1" "val1" "key2" "val2"
local ctx="$REPLY"
${ctx}::info   "message" [extra_key extra_val ...]
${ctx}::infof  "format %s" arg
${ctx}::error / warn / debug / errorf / warnf / debugf
zlog::remove_context "$ctx"
```

### Benchmarking

```zsh
zlog::benchmark        "label"  command [args]
zlog::benchmark_start  "label"  ;  timer="$REPLY"
zlog::benchmark_end    "$timer"
zlog::benchmark_block  "label"  <<'END'
  # code block
END
```

### Configuration

```zsh
zlog::setup              "/path/to/app.log"  [level]  [format]
zlog::set_level          error|warn|info|debug|0-3
zlog::set_file_level     error|warn|info|debug|0-3|-1|console
zlog::set_file           "/path/to/app.log"
zlog::set_format         text|json
zlog::set_rotation       0|1  [max_size]  [keep_count]
zlog::enable_buffering   [buffer_size]
zlog::disable_buffering
zlog::set_buffer_size    N
zlog::set_timestamp_format  "%Y-%m-%d %H:%M:%S"
zlog::show_config
zlog::show_stats
zlog::reset
zlog::flush
```

### Async

```zsh
zlog::enable_async
zlog::disable_async
zlog::is_async            # returns 0 if active
```

### Performance

```zsh
zlog::enable_performance_mode
zlog::disable_performance_mode
```

---

## 21. Data Flow: End-to-End

```mermaid
flowchart TD
    Call["zlog::info 'User logged in'\n'user' 'alice' 'ip' '1.2.3.4'"]

    FastFlag{"any_logging_enabled?"}
    Drop1["return 0 (no-op)"]

    LevelFilter{"level <= console_level\nOR level <= file_level?"}
    Drop2["return 0 (filtered)"]

    RateOnce{"rate_limit or\nonce check?"}
    Drop3["return 0 (suppressed)"]

    TS["Update timestamp cache\n(if epoch changed)"]

    Fmt{"format = text\nor json?"}
    FmtText["Build colored text line\nwith padded level name"]
    FmtJSON["Build JSON object\nwith escaped values"]

    Console{"should_console?"}
    ConOut["print -u2 formatted\n→ stderr"]

    FileCheck{"should_file?"}
    BufCheck{"buffered?"}
    BufAdd["_zlog_buffer += formatted\n(auto-flush if full or ERROR)"]
    AsyncCheck{"async active?"}
    AsyncOut["print -u async_fd formatted\n→ FIFO → worker → file"]
    DirectOut["print -r formatted >> logfile\n(with rotation check)"]

    Stats["_zlog_stats[messages_logged]++"]

    Call --> FastFlag
    FastFlag -->|no| Drop1
    FastFlag -->|yes| LevelFilter
    LevelFilter -->|filtered| Drop2
    LevelFilter -->|passes| RateOnce
    RateOnce -->|suppressed| Drop3
    RateOnce -->|passes| TS --> Fmt
    Fmt -->|text| FmtText
    Fmt -->|json| FmtJSON
    FmtText & FmtJSON --> Console
    Console -->|yes| ConOut --> FileCheck
    Console -->|no| FileCheck
    FileCheck -->|no| Stats
    FileCheck -->|yes| BufCheck
    BufCheck -->|yes| BufAdd --> Stats
    BufCheck -->|no| AsyncCheck
    AsyncCheck -->|yes| AsyncOut --> Stats
    AsyncCheck -->|no| DirectOut --> Stats
```

---

## 22. Naming Conventions

| Pattern | Meaning | Example |
|---|---|---|
| `zlog::<verb>` | Public API | `zlog::info` |
| `__zlog::<verb>` | Private internal | `__zlog::engine` |
| `__z::json::<verb>` | JSON utilities | `__z::json::escape` |
| `_zlog_<name>` | Global state variable | `_zlog_config` |
| `_ZLOG_<NAME>` | Readonly constant | `_ZLOG_LEVEL_INFO` |
| `zlog_ctx_PID_TS_RAND` | Context logger ID | `zlog_ctx_1234_1705329781_42` |
| `zbt_PID_TS_RAND` | Benchmark timer ID | `zbt_1234_1705329781_7` |

---

## 23. Design Principles

| Principle | Implementation |
|---|---|
| **Zero external dependencies** | Only `zsh/datetime` (optional), `tput`, `stat`, `date` as fallbacks |
| **Safe re-sourcing** | All globals guarded with `${+var}` checks |
| **No subshell for return values** | `REPLY` convention — avoids fork overhead |
| **Option isolation** | Every function uses `emulate -L zsh` + `setopt localoptions` |
| **Recursion safety** | `_zlog_state[depth]` counter, always restored in all code paths |
| **NO_COLOR compliance** | Respects the standard `NO_COLOR` environment variable |
| **Error suppression** | File write errors printed for first 5 occurrences, then silenced |
| **Graceful degradation** | Missing `stat` → no rotation; missing `strftime` → `date` fallback; no TTY → no colors |
| **Performance first** | Timestamp cache, fast-path flags, fast engine, `format_simple`, bulk flush |
| **Idempotent init** | `_zlog_initialized` flag prevents double-init work |
