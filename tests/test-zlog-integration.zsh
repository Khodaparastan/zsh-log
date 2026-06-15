#!/usr/bin/env zsh
# ==============================================================================
#  zlog — Integration Test Suite
#  Tests the public API end-to-end: output format, level filtering, context
#  loggers, control-flow helpers, benchmarking, buffering, and configuration.
#  Run from the repo root: zsh tests/test-zlog-integration.zsh
# ==============================================================================

emulate -L zsh
setopt err_return no_unset pipe_fail

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/../zlog"

###############################################################################
# Minimal test framework (same as unit suite)
###############################################################################

typeset -gi _t_count=0 _t_passed=0 _t_failed=0
typeset -ga _t_failures=()

_t_ok() {
  local desc="$1"
  (( _t_count++ )); (( _t_passed++ ))
  print "  ✓ $desc"
}

_t_fail() {
  local desc="$1" detail="${2:-}"
  (( _t_count++ )); (( _t_failed++ ))
  _t_failures+=("$desc")
  print "  ✗ $desc"
  [[ -n "$detail" ]] && print "    $detail"
}

assert_eq() {
  local expected="$1" actual="$2" desc="$3"
  if [[ "$actual" == "$expected" ]]; then _t_ok "$desc"
  else _t_fail "$desc" "expected='$expected' actual='$actual'"; fi
}

assert_contains() {
  local haystack="$1" needle="$2" desc="$3"
  if [[ "$haystack" == *"$needle"* ]]; then _t_ok "$desc"
  else _t_fail "$desc" "missing='$needle' in='$haystack'"; fi
}

assert_ne() {
  local not_expected="$1" actual="$2" desc="$3"
  if [[ "$actual" != "$not_expected" ]]; then _t_ok "$desc"
  else _t_fail "$desc" "should not equal '$not_expected'"; fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" desc="$3"
  if [[ "$haystack" != *"$needle"* ]]; then _t_ok "$desc"
  else _t_fail "$desc" "should not contain '$needle'"; fi
}

assert_rc() {
  local expected_rc="$1" actual_rc="$2" desc="$3"
  if (( actual_rc == expected_rc )); then _t_ok "$desc"
  else _t_fail "$desc" "expected rc=$expected_rc actual rc=$actual_rc"; fi
}

section() { print "\n── $1 ──────────────────────────────────────────────────────" }

summary() {
  print "\n╔════════════════════════════════════════════════════════════════╗"
  print "║               INTEGRATION TEST RESULTS                        ║"
  print "╚════════════════════════════════════════════════════════════════╝"
  print "  Total:  $_t_count"
  print "  Passed: $_t_passed"
  print "  Failed: $_t_failed"
  if (( _t_failed > 0 )); then
    print "\n  Failed tests:"
    local f; for f in "${_t_failures[@]}"; do print "    - $f"; done
    print ""
    return 1
  else
    print "\n  🎉 All tests passed!\n"
    return 0
  fi
}

# Temp log file used across tests
typeset -g TLOG="/tmp/zlog_test_$$.log"
cleanup_log() { setopt noglob; rm -f "${TLOG}"* 2>/dev/null; unsetopt noglob; true }
trap cleanup_log EXIT INT TERM

###############################################################################
# 1. setup & Configuration API
###############################################################################

test_setup_and_config() {
  section "setup & Configuration API"

  z::log::reset

  # setup with file
  z::log::setup "$TLOG" debug text
  assert_eq "$TLOG"  "${_zlog_config[file]}"   "setup: file set"
  assert_eq "3"      "${_zlog_config[level]}"  "setup: level=debug (3)"
  assert_eq "text"   "${_zlog_config[format]}" "setup: format=text"

  # setup console-only
  z::log::setup "-" info json
  assert_eq ""       "${_zlog_config[file]}"   "setup '-': file is empty"
  assert_eq "2"      "${_zlog_config[level]}"  "setup: level=info (2)"
  assert_eq "json"   "${_zlog_config[format]}" "setup: format=json"

  # set_level / get_level
  z::log::set_level warn
  local lvl; lvl=$(z::log::get_level)
  assert_eq "WARN" "$lvl" "get_level returns WARN after set_level warn"

  # set_format / get_format
  z::log::set_format text
  local fmt; fmt=$(z::log::get_format)
  assert_eq "text" "$fmt" "get_format returns text"

  # set_file / get_file
  z::log::set_file "$TLOG"
  local f; f=$(z::log::get_file)
  assert_eq "$TLOG" "$f" "get_file returns set path"

  # show_config runs without error
  local out; out=$(z::log::show_config 2>&1)
  assert_rc 0 $? "show_config exits 0"
  assert_contains "$out" "WARN" "show_config output contains current level"

  z::log::reset
  cleanup_log
}

###############################################################################
# 2. Core Logging — Text Format
###############################################################################

test_core_logging_text() {
  section "Core Logging — Text Format"

  z::log::reset
  z::log::setup "$TLOG" debug text

  z::log::error "Error occurred" host db.internal code 500
  z::log::warn  "High memory"   used_mb 1800
  z::log::info  "Server ready"  port 8080
  z::log::debug "Cache miss"    key session_42

  local content; content=$(cat "$TLOG")

  assert_contains "$content" "[ERROR]"       "ERROR tag present"
  assert_contains "$content" "[WARN ]"       "WARN tag present"
  assert_contains "$content" "[INFO ]"       "INFO tag present"
  assert_contains "$content" "[DEBUG]"       "DEBUG tag present"
  assert_contains "$content" "Error occurred" "Error message present"
  assert_contains "$content" "host=db.internal" "KV pair host present"
  assert_contains "$content" "code=500"      "KV pair code present"
  assert_contains "$content" "used_mb=1800"  "KV pair used_mb present"
  assert_contains "$content" "port=8080"     "KV pair port present"
  assert_contains "$content" "key=session_42" "KV pair key present"

  z::log::reset; cleanup_log
}

###############################################################################
# 3. Core Logging — JSON Format
###############################################################################

test_core_logging_json() {
  section "Core Logging — JSON Format"

  z::log::reset
  z::log::setup "$TLOG" debug json

  z::log::info "User login" actor alice ip 10.0.0.1

  local content; content=$(cat "$TLOG")
  assert_contains "$content" '"level"'    "JSON has level field"
  assert_contains "$content" '"message"'  "JSON has message field"
  assert_contains "$content" '"timestamp"' "JSON has timestamp field"
  assert_contains "$content" 'User login' "JSON has message value"
  assert_contains "$content" '"actor"'    "JSON has actor key"
  assert_contains "$content" '"alice"'    "JSON has actor value"
  assert_contains "$content" '"ip"'       "JSON has ip key"
  assert_contains "$content" '"10.0.0.1"' "JSON has ip value"

  z::log::reset; cleanup_log
}

###############################################################################
# 4. Printf-Style Logging
###############################################################################

test_printf_logging() {
  section "Printf-Style Logging"

  z::log::reset
  z::log::setup "$TLOG" debug text

  z::log::infof  "Processed %d items in %.2fs" 42 1.5
  z::log::warnf  "Memory at %d%%" 85
  z::log::errorf "Failed after %d retries" 3
  z::log::debugf "Cache hit rate: %.1f%%" 97.3

  local content; content=$(cat "$TLOG")
  assert_contains "$content" "Processed 42 items in 1.50s" "infof formats correctly"
  assert_contains "$content" "Memory at 85%"               "warnf formats correctly"
  assert_contains "$content" "Failed after 3 retries"      "errorf formats correctly"
  assert_contains "$content" "Cache hit rate: 97.3%"       "debugf formats correctly"

  z::log::reset; cleanup_log
}

###############################################################################
# 5. Level Filtering
###############################################################################

test_level_filtering() {
  section "Level Filtering"

  z::log::reset
  z::log::setup "$TLOG" warn text

  z::log::error "error-msg"
  z::log::warn  "warn-msg"
  z::log::info  "info-msg"
  z::log::debug "debug-msg"

  local content; content=$(cat "$TLOG")
  assert_contains     "$content" "error-msg" "ERROR passes warn filter"
  assert_contains     "$content" "warn-msg"  "WARN passes warn filter"
  assert_not_contains "$content" "info-msg"  "INFO blocked by warn filter"
  assert_not_contains "$content" "debug-msg" "DEBUG blocked by warn filter"

  z::log::reset; cleanup_log
}

###############################################################################
# 6. Generic z::log::log
###############################################################################

test_generic_log() {
  section "Generic z::log::log"

  z::log::reset
  z::log::setup "$TLOG" debug text

  z::log::log "info"  "via-name"
  z::log::log 2       "via-number"
  z::log::log "debug" "with-kv" key val

  local content; content=$(cat "$TLOG")
  assert_contains "$content" "via-name"   "log with level name works"
  assert_contains "$content" "via-number" "log with numeric level works"
  assert_contains "$content" "with-kv"    "log with KV works"
  assert_contains "$content" "key=val"    "log KV pair present"

  z::log::reset; cleanup_log
}

###############################################################################
# 7. Control-Flow Helpers
###############################################################################

test_control_flow() {
  section "Control-Flow Helpers"

  z::log::reset
  z::log::setup "$TLOG" info text

  # with_level — temporarily raises level
  z::log::with_level debug z::log::debug "debug-via-with_level"
  local content; content=$(cat "$TLOG")
  assert_contains "$content" "debug-via-with_level" "with_level raises level temporarily"

  # after with_level, level is restored
  z::log::debug "should-not-appear"
  content=$(cat "$TLOG")
  assert_not_contains "$content" "should-not-appear" "level restored after with_level"

  # silent — suppresses all output
  z::log::silent z::log::error "silenced-error"
  content=$(cat "$TLOG")
  assert_not_contains "$content" "silenced-error" "silent suppresses logging"

  # always — bypasses level filter
  z::log::set_level error
  z::log::always "always-msg" key val
  content=$(cat "$TLOG")
  assert_contains "$content" "always-msg" "always bypasses level filter"

  z::log::reset; cleanup_log
}

###############################################################################
# 8. Once & Rate Limiting
###############################################################################

test_once_and_rate_limit() {
  section "Once & Rate Limiting"

  z::log::reset
  z::log::setup "$TLOG" debug text

  # once — logs only on first call per key
  local i
  for i in {1..5}; do
    z::log::once "startup-key" info "startup-msg" iter $i
  done
  local count; count=$(grep -c "startup-msg" "$TLOG" 2>/dev/null || print 0)
  assert_eq "1" "$count" "once logs exactly once per key"

  # clear_once — allows re-logging
  z::log::clear_once "startup-key"
  z::log::once "startup-key" info "startup-msg-2"
  count=$(grep -c "startup-msg-2" "$TLOG" 2>/dev/null || print 0)
  assert_eq "1" "$count" "once logs again after clear_once"

  # rate_limit — caps messages per window
  local logged=0 limited=0
  for i in {1..10}; do
    if z::log::rate_limit "rl-key" 3 60 info "rate-limited-msg"; then
      (( logged++ ))
    else
      (( limited++ ))
    fi
  done
  assert_eq "3" "$logged"  "rate_limit allows exactly 3 messages"
  assert_eq "7" "$limited" "rate_limit blocks remaining 7"

  z::log::clear_rate_limits
  z::log::reset; cleanup_log
}

###############################################################################
# 9. Context Loggers
###############################################################################

test_context_loggers() {
  section "Context Loggers"

  z::log::reset
  z::log::setup "$TLOG" debug text

  z::log::with_context "request_id" "abc-123" "actor" "alice"
  local ctx="$REPLY"

  ${ctx}::info  "Request received"
  ${ctx}::warn  "Slow query" duration_ms 1500
  ${ctx}::error "Handler failed" code 500

  local content; content=$(cat "$TLOG")
  assert_contains "$content" "request_id=abc-123" "Context field request_id present"
  assert_contains "$content" "actor=alice"        "Context field actor present"
  assert_contains "$content" "Request received"   "Context info message present"
  assert_contains "$content" "Slow query"         "Context warn message present"
  assert_contains "$content" "Handler failed"     "Context error message present"
  assert_contains "$content" "duration_ms=1500"   "Extra KV on context call present"

  z::log::remove_context "$ctx"

  # After removal, context functions should be gone
  typeset -f "${ctx}::info" &>/dev/null
  assert_rc 1 $? "Context functions removed after remove_context"

  z::log::reset; cleanup_log
}

###############################################################################
# 10. Benchmarking
###############################################################################

test_benchmarking() {
  section "Benchmarking"

  z::log::reset
  z::log::setup "$TLOG" debug text

  # benchmark wraps a command and logs duration
  z::log::benchmark "import" sleep 0
  local content; content=$(cat "$TLOG")
  assert_contains "$content" "import"    "benchmark logs label"
  assert_contains "$content" "duration"  "benchmark logs duration field"

  # benchmark_start / benchmark_end
  z::log::benchmark_start "myop"
  local timer_id="$REPLY"
  sleep 0
  z::log::benchmark_end "$timer_id"
  content=$(cat "$TLOG")
  assert_contains "$content" "Benchmark completed: myop" "benchmark_end logs operation name"
  assert_contains "$content" "duration"                  "benchmark_end logs duration"

  z::log::reset; cleanup_log
}

###############################################################################
# 11. Buffering
###############################################################################

test_buffering() {
  section "Buffering"

  z::log::reset
  z::log::setup "$TLOG" debug text

  z::log::enable_buffering 10
  assert_eq "1" "${_zlog_config[buffered]}" "Buffering enabled"

  local i
  for i in {1..5}; do
    z::log::info "buffered-msg-$i"
  done

  # Before flush, messages may not be in file yet
  local count_before; count_before=$(grep -c "buffered-msg" "$TLOG" 2>/dev/null || print 0)

  z::log::flush
  local count_after; count_after=$(grep -c "buffered-msg" "$TLOG" 2>/dev/null || print 0)
  assert_eq "5" "$count_after" "All buffered messages flushed to file"

  z::log::disable_buffering
  assert_eq "0" "${_zlog_config[buffered]}" "Buffering disabled"

  z::log::reset; cleanup_log
}

###############################################################################
# 12. Statistics
###############################################################################

test_statistics() {
  section "Statistics"

  z::log::reset
  z::log::reset_stats
  z::log::setup "$TLOG" debug text

  z::log::info  "msg1"
  z::log::warn  "msg2"
  z::log::error "msg3"

  local stats; stats=$(z::log::get_stats)
  assert_contains "$stats" "Messages logged" "get_stats output has messages_logged"

  z::log::reset; cleanup_log
}

###############################################################################
# 13. Timestamp Utilities
###############################################################################

test_timestamps() {
  section "Timestamp Utilities"

  local ts
  z::log::get_timestamp human; ts="$REPLY"
  assert_contains "$ts" "-" "human timestamp contains date separator"

  z::log::get_timestamp iso; ts="$REPLY"
  assert_contains "$ts" "T" "ISO timestamp contains T separator"

  z::log::get_timestamp epoch; ts="$REPLY"
  assert_ne "" "$ts" "epoch timestamp is non-empty"

  z::log::enable_timestamp_cache
  assert_eq "1" "${_zlog_config[timestamp_cache_enabled]}" "Timestamp cache enabled"

  z::log::disable_timestamp_cache
  assert_eq "0" "${_zlog_config[timestamp_cache_enabled]}" "Timestamp cache disabled"

  z::log::enable_timestamp_cache
}

###############################################################################
# 14. File Rotation
###############################################################################

test_file_rotation() {
  section "File Rotation"

  z::log::reset
  z::log::setup "$TLOG" debug text
  z::log::set_rotation 1 "2KB" 3

  assert_eq "1"    "${_zlog_config[rotate]}"      "Rotation enabled"
  assert_eq "2048" "${_zlog_config[rotate_size]}" "Rotation size = 2KB"
  assert_eq "3"    "${_zlog_config[rotate_keep]}" "Rotation keep = 3"

  # Write enough to trigger rotation
  local i
  for i in {1..100}; do
    z::log::info "Rotation test message $i — padding to fill the file quickly"
  done

  # At least the main log file should exist
  [[ -f "$TLOG" ]]
  assert_rc 0 $? "Log file exists after writes"

  z::log::reset; cleanup_log
}

###############################################################################
# 15. Benchmark Block
###############################################################################

test_benchmark_block() {
  section "Benchmark Block"

  z::log::reset
  z::log::setup "$TLOG" debug text

  z::log::benchmark_block "block-op" <<'END'
    local x=0
    for i in {1..10}; do (( x += i )); done
END

  local content; content=$(cat "$TLOG")
  assert_contains "$content" "block-op"  "benchmark_block logs label"
  assert_contains "$content" "duration"  "benchmark_block logs duration field"

  z::log::reset; cleanup_log
}

###############################################################################
# 16. Performance Mode
###############################################################################

test_performance_mode() {
  section "Performance Mode"

  z::log::reset
  local perf_log="/tmp/zlog_test_perf_$$.log"
  z::log::setup "$perf_log" info text

  z::log::enable_performance_mode

  # Capture console output (fast engine writes to stderr)
  local console_out
  console_out=$(z::log::info "perf-mode-msg" key val 2>&1)

  z::log::disable_performance_mode

  assert_contains "$console_out" "perf-mode-msg" "Messages logged in performance mode"
  assert_eq "0" "${_zlog_config[debug_mode]}" "debug_mode disabled in performance mode aftermath"

  z::log::reset
  rm -f "$perf_log"
}

###############################################################################
# 17. Async Logging
###############################################################################

test_async_logging() {
  section "Async Logging"

  z::log::reset
  # Pre-initialize async config keys to avoid no_unset errors
  _zlog_config[async_pid]=""
  _zlog_config[async_fd]=""
  _zlog_config[async_fifo]=""
  local async_log="/tmp/zlog_test_async_$$.log"
  z::log::setup "$async_log" debug text

  z::log::enable_async
  local rc=$?
  assert_rc 0 $rc "enable_async returns 0 with file configured"

  z::log::is_async
  assert_rc 0 $? "is_async returns 0 after enable_async"

  local i
  for i in {1..5}; do
    z::log::info "async-msg-$i"
  done

  z::log::disable_async

  z::log::is_async
  assert_rc 1 $? "is_async returns 1 after disable_async"

  # Give async worker a moment to flush
  sleep 0.2
  local content; content=$(cat "$async_log" 2>/dev/null || print "")
  assert_contains "$content" "async-msg" "Async messages written to log file"

  z::log::reset
  rm -f "$async_log"
}

###############################################################################
# 18. reset
###############################################################################

test_reset() {
  section "reset"

  z::log::setup "$TLOG" debug json
  z::log::set_level error
  z::log::enable_buffering 100

  z::log::reset

  assert_eq "text" "${_zlog_config[format]}" "reset restores format to text"
  assert_eq ""     "${_zlog_config[file]}"   "reset clears file"
  assert_eq "0"    "${_zlog_config[buffered]}" "reset disables buffering"

  cleanup_log
}

###############################################################################
# Run all
###############################################################################

print "╔════════════════════════════════════════════════════════════════╗"
print "║              zlog — Integration Test Suite                    ║"
print "╚════════════════════════════════════════════════════════════════╝"

test_setup_and_config
test_core_logging_text
test_core_logging_json
test_printf_logging
test_level_filtering
test_generic_log
test_control_flow
test_once_and_rate_limit
test_context_loggers
test_benchmarking
test_benchmark_block
test_buffering
test_statistics
test_timestamps
test_file_rotation
test_performance_mode
test_async_logging
test_reset

summary
