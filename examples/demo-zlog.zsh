#!/usr/bin/env zsh
# ==============================================================================
#  zlog — Interactive Feature Demonstration
#  Run: zsh examples/demo-zlog.zsh
# ==============================================================================

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/../zlog"

typeset -g DEMO_LOG="/tmp/zlog_demo_$$.log"

_header() {
  print "\n╔════════════════════════════════════════════════════════════════╗"
  print "║          zlog — Interactive Feature Demonstration             ║"
  print "╚════════════════════════════════════════════════════════════════╝"
}

_section() { z::log::colorize bold "━━━ $1 ━━━"; print "\n$REPLY" }

###############################################################################
# Demo 1: Basic Logging
###############################################################################

demo_basic_logging() {
  _section "1. Basic Logging"

  z::log::setup "$DEMO_LOG" debug text

  z::log::error "Connection refused"  host db.internal retries 3
  z::log::warn  "High memory usage"   used_mb 1800 limit_mb 2048
  z::log::info  "Server started"      port 8080 env production
  z::log::debug "Cache initialized"   entries 0 capacity 1024
}

###############################################################################
# Demo 2: Printf-Style Formatting
###############################################################################

demo_printf_formatting() {
  _section "2. Printf-Style Formatting"

  z::log::infof  "Processed %d out of %d items (%.1f%% complete)" 75 100 75.0
  z::log::warnf  "Memory usage: %d MB (%.1f%% of available)"      1500 75.5
  z::log::errorf "Failed to connect to %s:%d after %ds timeout"   "db.internal" 5432 30
  z::log::debugf "Query returned %d rows in %.3fs"                 42 0.012
}

###############################################################################
# Demo 3: JSON Format
###############################################################################

demo_json_format() {
  _section "3. JSON Format"

  z::log::set_format json
  z::log::info  "Application started" version "1.0.0" environment production
  z::log::warn  "High memory detected" usage_mb 1500 threshold_mb 1200
  z::log::error "Database connection failed" error timeout retry_count 3
  z::log::set_format text
}

###############################################################################
# Demo 4: Level Filtering
###############################################################################

demo_level_filtering() {
  _section "4. Level Filtering"

  print "  → level=error (only errors)"
  z::log::set_level error
  z::log::error "This ERROR appears"
  z::log::warn  "This WARN is suppressed"
  z::log::info  "This INFO is suppressed"

  print "  → level=warn"
  z::log::set_level warn
  z::log::error "This ERROR appears"
  z::log::warn  "This WARN appears"
  z::log::info  "This INFO is suppressed"

  print "  → level=debug (everything)"
  z::log::set_level debug
  z::log::error "ERROR appears"
  z::log::warn  "WARN appears"
  z::log::info  "INFO appears"
  z::log::debug "DEBUG appears"

  z::log::set_level info
}

###############################################################################
# Demo 5: Context Loggers
###############################################################################

demo_context_loggers() {
  _section "5. Context Loggers"

  z::log::with_context "request_id" "req-7f3a" "user" "alice" "method" "POST"
  local ctx="$REPLY"

  ${ctx}::info  "Request received"
  ${ctx}::debug "Validating payload"   content_type application/json
  ${ctx}::warn  "Slow database query"  duration_ms 1250 threshold_ms 1000
  ${ctx}::info  "Request completed"    status 201 response_ms 1380

  z::log::remove_context "$ctx"
}

###############################################################################
# Demo 6: Control-Flow Helpers
###############################################################################

demo_control_flow() {
  _section "6. Control-Flow Helpers"

  z::log::set_level info

  # with_level: temporarily raise level for one call
  z::log::with_level debug z::log::debug "Debug detail (via with_level)"

  # silent: suppress all logging for one call
  z::log::silent z::log::error "This error is silenced"

  # always: bypass level filter
  z::log::set_level error
  z::log::always "Critical startup check passed" component auth
  z::log::set_level info

  # if_debug: guard expensive operations
  if z::log::if_debug; then
    z::log::debug "Expensive debug info gathered"
  else
    print "  (debug disabled — skipping expensive gather)"
  fi
}

###############################################################################
# Demo 7: Once & Rate Limiting
###############################################################################

demo_once_and_rate_limit() {
  _section "7. Once & Rate Limiting"

  print "  → z::log::once: logging 5 iterations, expect 1 log line"
  local i
  for i in {1..5}; do
    z::log::once "demo-once" warn "Deprecated config key detected" key old_timeout iter $i
  done
  z::log::clear_once "demo-once"

  print "  → z::log::rate_limit: 10 calls, limit 3 per 60s"
  local logged=0 limited=0
  for i in {1..10}; do
    if z::log::rate_limit "demo-rl" 3 60 info "Rate-limited event $i"; then
      (( logged++ ))
    else
      (( limited++ ))
    fi
  done
  print "    Logged: $logged  Limited: $limited"
  z::log::clear_rate_limits
}

###############################################################################
# Demo 8: Benchmarking
###############################################################################

demo_benchmarking() {
  _section "8. Benchmarking"

  # Wrap a single command
  z::log::benchmark "data-load" sleep 0.05

  # Manual start/end timing
  z::log::benchmark_start "processing"
  local _proc_timer="$REPLY"
  sleep 0.02
  z::log::benchmark_end "$_proc_timer"

  # Benchmark a heredoc block
  z::log::benchmark_block "full-pipeline" <<'END'
    local i
    for i in {1..5}; do sleep 0.01; done
END
}

###############################################################################
# Demo 9: Buffering
###############################################################################

demo_buffering() {
  _section "9. Buffering"

  # Log to file only during timing loops to avoid console flood
  z::log::set_file_level debug
  z::log::set_level error

  print "  → Without buffering (50 messages):"
  local start=$EPOCHREALTIME
  local i
  for i in {1..50}; do z::log::info "Unbuffered message $i"; done
  local dur_plain=$(( (EPOCHREALTIME - start) * 1000 ))

  print "  → With buffering (50 messages + flush):"
  z::log::enable_buffering 25
  start=$EPOCHREALTIME
  for i in {1..50}; do z::log::info "Buffered message $i"; done
  z::log::flush
  local dur_buf=$(( (EPOCHREALTIME - start) * 1000 ))
  z::log::disable_buffering

  z::log::set_level info
  z::log::set_file_level console
  printf "    Plain: %.1fms   Buffered: %.1fms\n" "$dur_plain" "$dur_buf"
}

###############################################################################
# Demo 10: Async Logging
###############################################################################

demo_async_logging() {
  _section "10. Async Logging"

  local async_log="/tmp/zlog_demo_async_$$.log"
  z::log::set_file "$async_log"
  z::log::enable_async

  print "  → Async worker running: $(z::log::is_async && print yes || print no)"

  z::log::set_file_level debug
  z::log::set_level error
  local i
  for i in {1..20}; do
    z::log::info "Async event $i" worker background
  done
  z::log::set_level info
  z::log::set_file_level console

  z::log::disable_async
  sleep 0.2
  print "  → Async worker running: $(z::log::is_async && print yes || print no)"
  print "  → Lines written: $(wc -l < "$async_log" 2>/dev/null || print 0)"

  rm -f "$async_log"
  z::log::set_file "$DEMO_LOG"
}

###############################################################################
# Demo 11: Performance Mode
###############################################################################

demo_performance_mode() {
  _section "11. Performance Mode"

  z::log::enable_buffering 500
  z::log::enable_performance_mode

  print "  → Fast engine active — logging a few messages:"
  z::log::info  "Perf event" type fast_engine
  z::log::warn  "Perf event" type fast_engine
  z::log::error "Perf event" type fast_engine

  z::log::disable_performance_mode
  z::log::disable_buffering

  print "  → Performance mode disabled, back to normal engine"
}

###############################################################################
# Demo 12: File Rotation
###############################################################################

demo_file_rotation() {
  _section "12. File Rotation"

  local rot_log="/tmp/zlog_demo_rot_$$.log"
  z::log::set_file "$rot_log"
  z::log::set_rotation 1 "1KB" 3

  print "  Writing messages to trigger rotation (limit: 1KB, keep: 3)..."
  z::log::set_file_level debug
  z::log::set_level error
  local i
  for i in {1..20}; do
    z::log::info "Rotation test message $i — padding to reach size limit quickly"
  done
  z::log::set_level info
  z::log::set_file_level console

  print "  Rotated files:"
  local rot_line
  ls -lh "${rot_log}"* 2>/dev/null | while IFS= read -r rot_line; do
    print "    $rot_line"
  done

  rm -f "${rot_log}"*
  z::log::set_file "$DEMO_LOG"
  z::log::set_rotation 0
}

###############################################################################
# Demo 13: Configuration Display
###############################################################################

demo_configuration() {
  _section "13. Configuration Display"
  z::log::show_config
}

###############################################################################
# Main
###############################################################################

run_demo() {
  _header

  z::log::colorize cyan "$DEMO_LOG"
  print "\nLogging to: $REPLY"

  demo_basic_logging
  demo_printf_formatting
  demo_json_format
  demo_level_filtering
  demo_context_loggers
  demo_control_flow
  demo_once_and_rate_limit
  demo_benchmarking
  demo_buffering
  demo_async_logging
  demo_performance_mode
  demo_file_rotation
  demo_configuration

  z::log::colorize bold '━━━ Log File Sample (last 20 lines) ━━━'
  print "\n$REPLY"
  z::log::colorize dim '────────────────────────────────────────────────────────────────'
  print "$REPLY"
  tail -20 "$DEMO_LOG" 2>/dev/null || print "(no file output)"
  z::log::colorize dim '────────────────────────────────────────────────────────────────'
  print "$REPLY"

  z::log::colorize green '✓ Demo complete.'
  print "\n$REPLY  Full log: $DEMO_LOG"

  z::log::cleanup
}

if [[ "${ZSH_EVAL_CONTEXT}" == "toplevel" ]]; then
  run_demo
fi
