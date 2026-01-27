# zsh-log

A high-performance, feature-rich logging library for Zsh with structured logging, contextual logging, benchmarking, and multiple output formats.

## Features

- 🎯 **Multi-level logging** (ERROR, WARN, INFO, DEBUG)
- 🎨 **Colored console output** with automatic terminal detection
- 📝 **Multiple formats** (text and JSON)
- 📁 **File logging** with automatic rotation
- ⚡ **Performance optimized** with caching and lazy evaluation
- 🔖 **Contextual logging** with dynamic context creation
- ⏱️ **Built-in benchmarking** for performance monitoring
- 🛡️ **Safe by default** with recursion protection and resource limits
- 📦 **Buffered logging** for high-throughput scenarios

## Installation

```zsh
# Source the library in your .zshrc or script
source /path/to/zlog.zsh

# Initialize colors (optional, done automatically on first use)
__z::log::init_colors
```

## Quick Start

```zsh
# Basic logging
z::log::info "Application started"
z::log::warn "Configuration file not found, using defaults"
z::log::error "Failed to connect to database"
z::log::debug "Request payload: ${payload}"

# Formatted logging (printf-style)
z::log::infof "Processing %d items in %.2f seconds" 100 1.23
z::log::errorf "Connection failed after %d attempts" 3

# Logging with context fields
z::log::info "User login successful" "user" "alice" "ip" "192.168.1.1"
z::log::error "Payment failed" "amount" "99.99" "currency" "USD" "reason" "insufficient_funds"
```

## Configuration

### Log Levels

```zsh
# Set console log level (0=ERROR, 1=WARN, 2=INFO, 3=DEBUG)
_zcore_logging[level]=2  # INFO (default)

# Set file log level independently (-1 = follow console level)
_zcore_logging[file_level]=3  # DEBUG to file, INFO to console
```

### Output Format

```zsh
# Text format (default, colored)
_zcore_logging[format]="text"

# JSON format (structured logging)
_zcore_logging[format]="json"
```

**Text Output Example:**
```
2026-01-27 10:30:45 [INFO]  (12345) User logged in | user=alice ip=192.168.1.1
2026-01-27 10:30:46 [ERROR] (12345) Connection timeout | host=db.example.com port=5432
```

**JSON Output Example:**
```json
{"timestamp":"2026-01-27T10:30:45+0000","level":"INFO","message":"User logged in","hostname":"server01","pid":12345,"user":"admin","user":"alice","ip":"192.168.1.1"}
{"timestamp":"2026-01-27T10:30:46+0000","level":"ERROR","message":"Connection timeout","hostname":"server01","pid":12345,"user":"admin","host":"db.example.com","port":"5432"}
```

### File Logging

```zsh
# Enable file logging
_zcore_logging[file]="/var/log/myapp.log"

# Configure rotation (10MB default)
_zcore_logging[rotate_size]=10485760  # 10MB
_zcore_logging[rotate_keep]=5         # Keep 5 old files

# Disable rotation
_zcore_logging[rotate_size]=0
```

### Buffered Logging

For high-throughput scenarios, enable buffering to reduce I/O:

```zsh
# Enable buffering (buffer up to 50 messages)
z::log::enable_buffering 50

# Manually flush buffer
z::log::flush

# Disable buffering (auto-flushes)
z::log::disable_buffering

# Note: Errors always flush immediately
```

### Timestamp Caching

```zsh
# Disable timestamp caching (for sub-second precision)
z::log::disable_timestamp_cache

# Re-enable (default, caches per second)
z::log::enable_timestamp_cache
```

## Advanced Features

### Contextual Logging

Create logging contexts with persistent key-value pairs:

```zsh
# Create a context
ctx=$(z::log::with_context "module" "auth" "session" "abc123" "user" "alice")

# Use context-specific logging functions
$ctx::info "Login attempt"
$ctx::warn "Invalid password"
$ctx::error "Account locked"

# Formatted logging with context
$ctx::infof "Login successful after %d attempts" 2

# Additional fields can be added per message
$ctx::info "Action performed" "action" "password_reset" "ip" "192.168.1.1"

# Remove context when done
z::log::remove_context "$ctx"

# Or remove all contexts
z::log::remove_all_contexts

# List active contexts
z::log::list_contexts
```

**Output Example:**
```
2026-01-27 10:30:45 [INFO] (12345) Login attempt | module=auth session=abc123 user=alice
2026-01-27 10:30:46 [WARN] (12345) Invalid password | module=auth session=abc123 user=alice
```

### Benchmarking

#### One-Shot Benchmark

```zsh
# Benchmark a command
z::log::benchmark "database_query" psql -c "SELECT * FROM users"

# Benchmark with complex commands
z::log::benchmark "api_call" curl -s https://api.example.com/data

# Benchmark a function
z::log::benchmark "data_processing" process_data "$input_file"
```

**Output:**
```
2026-01-27 10:30:45 [INFO] (12345) Benchmark: database_query | duration=123.45ms exit_code=0
```

#### Manual Timing

```zsh
# Start timer
timer=$(z::log::benchmark_start "complex_operation")

# Perform operations
download_data
process_data
upload_results

# End timer
z::log::benchmark_end "$timer"
```

**Output:**
```
2026-01-27 10:30:50 [INFO] (12345) Benchmark completed: complex_operation | duration=5.23s
```

### Conditional Logging

Avoid expensive operations when logging is disabled:

```zsh
# Check if level is active before expensive operations
if z::log::if_debug; then
  local debug_info=$(generate_expensive_debug_data)
  z::log::debug "Debug data: ${debug_info}"
fi

# Available checks
z::log::if_error  # Returns 0 if ERROR level active
z::log::if_warn   # Returns 0 if WARN level active
z::log::if_info   # Returns 0 if INFO level active
z::log::if_debug  # Returns 0 if DEBUG level active
```

## API Reference

### Core Logging Functions

| Function | Description |
|:---------|:------------|
| `z::log::error <message> [key val ...]` | Log error message with optional context |
| `z::log::warn <message> [key val ...]` | Log warning message with optional context |
| `z::log::info <message> [key val ...]` | Log info message with optional context |
| `z::log::debug <message> [key val ...]` | Log debug message with optional context |
| `z::log::errorf <format> [args ...]` | Log formatted error message |
| `z::log::warnf <format> [args ...]` | Log formatted warning message |
| `z::log::infof <format> [args ...]` | Log formatted info message |
| `z::log::debugf <format> [args ...]` | Log formatted debug message |

### Conditional Checks

| Function | Description |
|:---------|:------------|
| `z::log::if_error` | Returns 0 if ERROR level is active |
| `z::log::if_warn` | Returns 0 if WARN level is active |
| `z::log::if_info` | Returns 0 if INFO level is active |
| `z::log::if_debug` | Returns 0 if DEBUG level is active |

### Context Management

| Function | Description |
|:---------|:------------|
| `z::log::with_context <key> <val> ...` | Create logging context, returns context ID |
| `z::log::remove_context <ctx_id>` | Remove specific context |
| `z::log::remove_all_contexts` | Remove all contexts |
| `z::log::list_contexts` | List all active contexts |
| `$ctx::error <message> [key val ...]` | Log error with context |
| `$ctx::warn <message> [key val ...]` | Log warning with context |
| `$ctx::info <message> [key val ...]` | Log info with context |
| `$ctx::debug <message> [key val ...]` | Log debug with context |
| `$ctx::errorf <format> [args ...]` | Log formatted error with context |
| `$ctx::warnf <format> [args ...]` | Log formatted warning with context |
| `$ctx::infof <format> [args ...]` | Log formatted info with context |
| `$ctx::debugf <format> [args ...]` | Log formatted debug with context |

### Benchmarking

| Function | Description |
|:---------|:------------|
| `z::log::benchmark <name> <command> [args ...]` | Benchmark command execution |
| `z::log::benchmark_start <name>` | Start timer, returns timer ID |
| `z::log::benchmark_end <timer_id>` | End timer and log duration |

### Buffer Management

| Function | Description |
|:---------|:------------|
| `z::log::enable_buffering [size]` | Enable buffering (default 50 messages) |
| `z::log::disable_buffering` | Disable buffering and flush |
| `z::log::flush` | Manually flush buffer to file |

### Cache Control

| Function | Description |
|:---------|:------------|
| `z::log::enable_timestamp_cache` | Enable timestamp caching (default) |
| `z::log::disable_timestamp_cache` | Disable for sub-second precision |

### Utility Functions

| Function | Description |
|:---------|:------------|
| `z::ui::color <color> <text>` | Colorize text (red, green, yellow, blue, magenta, cyan, white, black, bold, dim) |
| `__z::log::init_colors` | Initialize color codes (auto-called) |

## Configuration Variables

### Global Settings

```zsh
typeset -gA _zcore_logging=(
  # Log levels (numeric)
  [error]=0
  [warn]=1
  [info]=2
  [debug]=3

  # Current configuration
  [level]=2              # Console log level (INFO)
  [format]="text"        # Output format: "text" or "json"
  [file]=""              # Log file path (empty = console only)
  [file_level]=-1        # File log level (-1 = follow console)

  # File rotation
  [rotate_size]=10485760 # 10MB default
  [rotate_keep]=5        # Keep 5 old files

  # Performance settings
  [max_depth]=5          # Recursion protection
  [buffered]=0           # Buffering disabled by default
  [timestamp_cache_enabled]=1  # Timestamp caching enabled
)
```

### Resource Limits

```zsh
typeset -gi _ZCORE_MAX_CONTEXTS=100  # Maximum active contexts
typeset -gi _ZCORE_MAX_TIMERS=50     # Maximum active timers
typeset -gi _zcore_buffer_max=50     # Buffer size
```

## Examples

### Simple Application Logging

```zsh
#!/usr/bin/env zsh
source zlog.zsh

# Configure
_zcore_logging[level]=2  # INFO
_zcore_logging[file]="/var/log/myapp.log"

# Application code
z::log::info "Application starting"

if ! connect_database; then
  z::log::error "Database connection failed" "host" "$DB_HOST" "port" "$DB_PORT"
  exit 1
fi

z::log::info "Processing records"
process_records

z::log::info "Application finished"
```

### Structured Logging with JSON

```zsh
#!/usr/bin/env zsh
source zlog.zsh

# Configure for JSON output
_zcore_logging[format]="json"
_zcore_logging[file]="/var/log/myapp.json"

# Log structured events
z::log::info "user_login" \
  "user_id" "12345" \
  "username" "alice" \
  "ip" "192.168.1.1" \
  "user_agent" "Mozilla/5.0"

z::log::info "payment_processed" \
  "transaction_id" "tx_abc123" \
  "amount" "99.99" \
  "currency" "USD" \
  "status" "success"
```

### Request Logging with Context

```zsh
#!/usr/bin/env zsh
source zlog.zsh

handle_request() {
  local request_id="req_${RANDOM}_${EPOCHSECONDS}"
  
  # Create request context
  local ctx=$(z::log::with_context \
    "request_id" "$request_id" \
    "method" "$1" \
    "path" "$2")
  
  $ctx::info "Request started"
  
  # Process request
  if ! process_request "$@"; then
    $ctx::error "Request failed" "error" "$?"
    z::log::remove_context "$ctx"
    return 1
  fi
  
  $ctx::info "Request completed"
  z::log::remove_context "$ctx"
  return 0
}

handle_request "GET" "/api/users"
```

### Performance Monitoring

```zsh
#!/usr/bin/env zsh
source zlog.zsh

# Enable buffering for high-throughput
z::log::enable_buffering 100

# Benchmark critical operations
z::log::benchmark "database_migration" run_migration

# Manual timing for complex workflows
timer=$(z::log::benchmark_start "data_pipeline")

z::log::info "Extracting data"
extract_data

z::log::info "Transforming data"
transform_data

z::log::info "Loading data"
load_data

z::log::benchmark_end "$timer"

# Flush remaining logs
z::log::flush
```

### Multi-Level Debugging

```zsh
#!/usr/bin/env zsh
source zlog.zsh

# Set debug level for development
_zcore_logging[level]=3  # DEBUG

z::log::debug "Entering function" "args" "$*"

if z::log::if_debug; then
  # Only compute expensive debug info when needed
  local memory_usage=$(ps -o rss= -p $$)
  z::log::debug "Memory usage: ${memory_usage}KB"
fi

z::log::info "Processing item" "id" "$item_id"
z::log::debug "Item details" "size" "$size" "type" "$type"
```

### Error Handling Pattern

```zsh
#!/usr/bin/env zsh
source zlog.zsh

safe_operation() {
  local operation="$1"
  shift
  
  z::log::info "Starting: $operation"
  
  if ! "$@"; then
    local exit_code=$?
    z::log::error "Operation failed: $operation" \
      "exit_code" "$exit_code" \
      "command" "$*"
    return $exit_code
  fi
  
  z::log::info "Completed: $operation"
  return 0
}

safe_operation "backup" rsync -av /data /backup
safe_operation "cleanup" rm -rf /tmp/cache/*
```

## Performance Considerations

### Timestamp Caching
- Enabled by default, caches timestamps per second
- Disable for sub-second precision: `z::log::disable_timestamp_cache`

### Lazy Evaluation
- Log levels checked before formatting
- Use conditional checks for expensive operations:
  ```zsh
  if z::log::if_debug; then
    z::log::debug "Expensive: $(expensive_operation)"
  fi
  ```

### Buffered Logging
- Reduces I/O overhead for high-throughput scenarios
- Errors always flush immediately
- Auto-flushes on EXIT, INT, TERM, HUP, QUIT signals

### Resource Limits
- Max 100 contexts (oldest auto-cleaned)
- Max 50 timers (oldest auto-cleaned)
- Configurable buffer size (default 50)

## Safety Features

- **Recursion protection**: Max depth of 5 to prevent infinite loops
- **Collision-resistant IDs**: Random + timestamp + PID for contexts and timers
- **Input validation**: Context keys validated (alphanumeric, `_`, `-` only)
- **Graceful degradation**: Continues on color/tput failures
- **Timeout protection**: File writes timeout after 1-2 seconds

## Color Support

Colors automatically disabled when:
- Output is not a TTY (`[[ ! -t 2 ]]`)
- `NO_COLOR` environment variable is set
- `TERM=dumb`

Available colors: `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`, `black`, `bold`, `dim`, `blink`


