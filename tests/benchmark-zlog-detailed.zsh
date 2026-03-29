#!/usr/bin/env zsh
# ==============================================================================
#  zlog — Detailed Benchmark: Normal vs Performance Mode Comparison
#  Provides a side-by-side comparison of normal and performance-mode throughput
#  across key logging scenarios.
#  Run from the repo root: zsh tests/benchmark-zlog-detailed.zsh
# ==============================================================================

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/../zlog"

typeset -g  BENCH_DIR="/tmp/zlog_bench_detail_$$"
typeset -gA NORMAL_RESULTS=()
typeset -gA PERF_RESULTS=()

###############################################################################
# Utilities
###############################################################################

setup() {
  mkdir -p "$BENCH_DIR"
  z::log::reset

  print "╔════════════════════════════════════════════════════════════════╗"
  print "║         zlog — Detailed Mode Comparison Benchmark             ║"
  print "╠════════════════════════════════════════════════════════════════╣"
  printf "║  Zsh:    %-53s║\n" "$ZSH_VERSION"
  printf "║  System: %-53s║\n" "$(uname -s) $(uname -m)"
  print "╚════════════════════════════════════════════════════════════════╝"
  print
}

cleanup() {
  rm -rf "$BENCH_DIR"
  z::log::cleanup
}

# time_iters <iterations> <cmd> [args...]  → sets REPLY to elapsed ms
time_iters() {
  local iters="$1"; shift
  "$@" &>/dev/null   # warmup
  local start=$EPOCHREALTIME
  local i
  for (( i = 0; i < iters; i++ )); do
    "$@" &>/dev/null
  done
  REPLY=$(( (EPOCHREALTIME - start) * 1000 ))
}

_section() { print "\n$(z::log::colorize bold "━━━ $1 ━━━")" }

###############################################################################
# Comparison runner
###############################################################################

# compare <label> <iterations> <cmd> [args...]
# Runs cmd in normal mode, then performance mode, prints side-by-side result.
compare() {
  local label="$1" iters="$2"; shift 2

  # Normal mode
  z::log::disable_performance_mode
  time_iters "$iters" "$@"
  local normal_ms="$REPLY"
  local normal_per=$(( normal_ms / iters ))
  NORMAL_RESULTS[$label]="${normal_ms}:${normal_per}"

  # Performance mode
  z::log::enable_performance_mode
  time_iters "$iters" "$@"
  local perf_ms="$REPLY"
  local perf_per=$(( perf_ms / iters ))
  PERF_RESULTS[$label]="${perf_ms}:${perf_per}"
  z::log::disable_performance_mode

  # Speedup
  local speedup=1
  (( normal_ms > 0 )) && speedup=$(( normal_ms * 10 / (perf_ms > 0 ? perf_ms : 1) ))
  local speedup_int=$(( speedup / 10 ))
  local speedup_dec=$(( speedup % 10 ))

  printf "  %-38s  normal: %7.2f ms  perf: %7.2f ms  speedup: %d.%dx\n" \
    "$label" "$normal_ms" "$perf_ms" "$speedup_int" "$speedup_dec"
}

###############################################################################
# Benchmark scenarios
###############################################################################

bench_console_logging() {
  _section "Console Logging"

  z::log::setup "-" debug text

  compare "error — no fields"          200 z::log::error "Error message"
  compare "warn  — no fields"          200 z::log::warn  "Warning message"
  compare "info  — no fields"          200 z::log::info  "Info message"
  compare "debug — no fields"          200 z::log::debug "Debug message"
  compare "info  — 4 fields"           200 z::log::info  "Info message" k1 v1 k2 v2
  compare "info  — 8 fields"           200 z::log::info  "Info message" k1 v1 k2 v2 k3 v3 k4 v4
}

bench_file_logging() {
  _section "File Logging (text)"

  local log="$BENCH_DIR/file.log"
  z::log::setup "$log" debug text

  compare "info — file, no fields"     200 z::log::info "File message"
  compare "info — file, 4 fields"      200 z::log::info "File message" k1 v1 k2 v2

  z::log::reset
}

bench_json_logging() {
  _section "File Logging (JSON)"

  local log="$BENCH_DIR/json.log"
  z::log::setup "$log" debug json

  compare "info — JSON, no fields"     200 z::log::info "JSON message"
  compare "info — JSON, 4 fields"      200 z::log::info "JSON message" k1 v1 k2 v2

  z::log::reset
}

bench_buffered_logging() {
  _section "Buffered File Logging"

  local log="$BENCH_DIR/buf.log"
  z::log::setup "$log" debug text
  z::log::enable_buffering 500

  compare "info — buffered, no fields" 200 z::log::info "Buffered message"
  compare "info — buffered, 4 fields"  200 z::log::info "Buffered message" k1 v1 k2 v2

  z::log::flush
  z::log::disable_buffering
  z::log::reset
}

bench_level_filtering() {
  _section "Level Filtering (inactive level)"

  z::log::setup "-" error text   # only errors pass

  compare "debug — filtered out"       1000 z::log::debug "Filtered debug"
  compare "info  — filtered out"       1000 z::log::info  "Filtered info"
  compare "warn  — filtered out"       1000 z::log::warn  "Filtered warn"

  z::log::reset
}

bench_printf_logging() {
  _section "Printf-Style Logging"

  z::log::setup "-" debug text

  compare "infof  — 2 args"            200 z::log::infof  "Processed %d items in %.2fs" 42 1.5
  compare "warnf  — 1 arg"             200 z::log::warnf  "Memory at %d%%" 85
  compare "errorf — 1 arg"             200 z::log::errorf "Failed after %d retries" 3

  z::log::reset
}

###############################################################################
# Summary table
###############################################################################

print_summary() {
  _section "Summary"

  print "  Scenario totals (normal vs performance mode):"
  print ""
  printf "  %-38s  %12s  %12s  %10s\n" "Scenario" "Normal (ms)" "Perf (ms)" "Speedup"
  printf "  %-38s  %12s  %12s  %10s\n" \
    "$(printf '%.0s─' {1..38})" "$(printf '%.0s─' {1..12})" \
    "$(printf '%.0s─' {1..12})" "$(printf '%.0s─' {1..10})"

  local key
  for key in "${(@k)NORMAL_RESULTS}"; do
    local n="${NORMAL_RESULTS[$key]%%:*}"
    local p="${PERF_RESULTS[$key]%%:*}"
    local speedup=1
    (( n > 0 && p > 0 )) && speedup=$(( n * 10 / p ))
    printf "  %-38s  %12.2f  %12.2f  %7d.%dx\n" \
      "$key" "$n" "$p" "$(( speedup / 10 ))" "$(( speedup % 10 ))"
  done

  print ""
  print "  $(z::log::colorize cyan 'Recommendations:')"
  print "  • Performance mode gives the largest gains on hot paths (filtered levels)"
  print "  • Buffering + performance mode is the fastest combination for file logging"
  print "  • JSON format is slower than text due to escaping; use text in hot loops"
  print "  • Printf-style functions have negligible overhead vs direct calls"
}

###############################################################################
# Main
###############################################################################

run_comparison() {
  setup

  bench_console_logging
  bench_file_logging
  bench_json_logging
  bench_buffered_logging
  bench_level_filtering
  bench_printf_logging

  print_summary

  cleanup
}

if [[ "${ZSH_EVAL_CONTEXT}" == "toplevel" ]]; then
  run_comparison
fi
