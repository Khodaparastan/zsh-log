#!/usr/bin/env zsh
# ==============================================================================
#  zlog — Production Benchmark Suite
#
#  Measures core subsystem costs and end-to-end logging throughput with:
#    * isolated temp directory
#    * warmup iterations
#    * configurable rounds
#    * median/min/mean/max timing
#    * per-op microseconds
#    * ops/sec
#    * optional CSV output
#    * optional async benchmark
#
#  Run:
#    zsh tests/benchmark-zlog.zsh
#    zsh tests/benchmark-zlog.zsh --quick
#    zsh tests/benchmark-zlog.zsh --rounds 7 --filter json
#    zsh tests/benchmark-zlog.zsh --csv /tmp/zlog-bench.csv
#    zsh tests/benchmark-zlog.zsh --include-async
# ==============================================================================

emulate zsh
setopt no_aliases extended_glob pipe_fail
unsetopt err_return

typeset -g SCRIPT_DIR="${0:A:h}"
typeset -g REPO_ROOT="${SCRIPT_DIR:h}"
typeset -g ZLOG_PATH="${ZLOG_PATH:-${REPO_ROOT}/zlog}"

if [[ ! -r "$ZLOG_PATH" ]]; then
  print -r -u2 -- "benchmark-zlog: cannot read zlog at: $ZLOG_PATH"
  exit 1
fi

source "$ZLOG_PATH" || {
  print -r -u2 -- "benchmark-zlog: failed to source: $ZLOG_PATH"
  exit 1
}

zmodload zsh/datetime 2>/dev/null || {
  print -r -u2 -- "benchmark-zlog: zsh/datetime is required"
  exit 1
}

###############################################################################
# Configuration
###############################################################################

typeset -g BENCH_DIR=""
typeset -gi BENCH_ROUNDS=5
typeset -gi BENCH_QUICK=0
typeset -gi BENCH_INCLUDE_ASYNC=0
typeset -g BENCH_FILTER=""
typeset -g BENCH_CSV=""

typeset -ga BENCH_ORDER=()
typeset -gA BENCH_GROUP=()
typeset -gA BENCH_LABEL=()
typeset -gA BENCH_ITERS=()
typeset -gA BENCH_MIN_MS=()
typeset -gA BENCH_MEDIAN_MS=()
typeset -gA BENCH_MEAN_MS=()
typeset -gA BENCH_MAX_MS=()
typeset -gA BENCH_PER_OP_US=()
typeset -gA BENCH_OPS_SEC=()

typeset -g BENCH_LARGE_STRING=""
typeset -g BENCH_CTX=""
typeset -g BENCH_CTX_INFO=""

###############################################################################
# CLI
###############################################################################

bench_usage() {
  print -r -- "Usage: zsh tests/benchmark-zlog.zsh [options]"
  print -r -- ""
  print -r -- "Options:"
  print -r -- "  --quick              Reduce iterations and rounds"
  print -r -- "  --rounds N           Number of timing rounds per case (default: 5)"
  print -r -- "  --filter TEXT        Run only cases whose group or label contains TEXT"
  print -r -- "  --csv PATH           Write CSV results to PATH"
  print -r -- "  --include-async      Include experimental async benchmark"
  print -r -- "  --help               Show this help"
}

bench_parse_args() {
  emulate -L zsh
  setopt localoptions no_unset

  while (( $# > 0 )); do
    case "$1" in
      --quick)
        BENCH_QUICK=1
        BENCH_ROUNDS=3
        ;;
      --rounds)
        shift
        if [[ ! "${1-}" =~ '^[0-9]+$' ]] || (( $1 < 1 )); then
          print -r -u2 -- "benchmark-zlog: --rounds requires a positive integer"
          return 2
        fi
        BENCH_ROUNDS="$1"
        ;;
      --filter)
        shift
        BENCH_FILTER="${1-}"
        ;;
      --csv)
        shift
        BENCH_CSV="${1-}"
        if [[ -z "$BENCH_CSV" ]]; then
          print -r -u2 -- "benchmark-zlog: --csv requires a path"
          return 2
        fi
        ;;
      --include-async)
        BENCH_INCLUDE_ASYNC=1
        ;;
      --help|-h)
        bench_usage
        return 99
        ;;
      *)
        print -r -u2 -- "benchmark-zlog: unknown option: $1"
        bench_usage >&2
        return 2
        ;;
    esac
    shift
  done

  return 0
}

###############################################################################
# Environment
###############################################################################

bench_make_dir() {
  emulate -L zsh
  setopt localoptions no_unset

  local base="${TMPDIR:-/tmp}"
  base="${base%/}"

  local -i i
  local dir_path
  for (( i = 0; i < 100; i++ )); do
    dir_path="${base}/zlog-bench.$$.$RANDOM.$i"
    if mkdir -m 700 "$dir_path" 2>/dev/null; then
      BENCH_DIR="$dir_path"
      return 0
    fi
  done

  print -r -u2 -- "benchmark-zlog: failed to create benchmark directory under $base"
  return 1
}

bench_cleanup() {
  emulate -L zsh
  setopt localoptions

  (( ${+functions[z::log::disable_performance_mode]} )) && z::log::disable_performance_mode >/dev/null 2>&1 || true
  (( ${+functions[z::log::disable_async]} )) && z::log::disable_async >/dev/null 2>&1 || true
  (( ${+functions[z::log::cleanup]} )) && z::log::cleanup >/dev/null 2>&1 || true

  if [[ -n "$BENCH_DIR" && -d "$BENCH_DIR" ]]; then
    rm -rf -- "$BENCH_DIR"
  fi
}

bench_setup() {
  emulate -L zsh
  setopt localoptions

  z::log::reset >/dev/null 2>&1 || true
  z::log::set_color_mode none >/dev/null 2>&1 || true
  z::log::enable_timestamp_cache >/dev/null 2>&1 || true

  local -i i
  BENCH_LARGE_STRING=""
  for (( i = 0; i < 2048; i++ )); do
    BENCH_LARGE_STRING+="x"
  done

  if [[ -n "$BENCH_CSV" ]]; then
    print -r -- "group,label,iterations,rounds,min_ms,median_ms,mean_ms,max_ms,per_op_us,ops_sec" > "$BENCH_CSV"
  fi

  local sys_name sys_arch
  sys_name="$(uname -s 2>/dev/null || print -r -- unknown)"
  sys_arch="$(uname -m 2>/dev/null || print -r -- unknown)"

  print -r -- "╔════════════════════════════════════════════════════════════════╗"
  print -r -- "║              zlog — Production Benchmark Suite                ║"
  print -r -- "╠════════════════════════════════════════════════════════════════╣"
  printf "║  Bench dir: %-50s║\n" "$BENCH_DIR"
  printf "║  Zsh:       %-50s║\n" "$ZSH_VERSION"
  printf "║  System:    %-50s║\n" "${sys_name} ${sys_arch}"
  printf "║  Rounds:    %-50s║\n" "$BENCH_ROUNDS"
  printf "║  Mode:      %-50s║\n" "$([[ $BENCH_QUICK == 1 ]] && print -r -- quick || print -r -- full)"
  if [[ -n "$BENCH_FILTER" ]]; then
    printf "║  Filter:    %-50s║\n" "$BENCH_FILTER"
  fi
  print -r -- "╚════════════════════════════════════════════════════════════════╝"
  print -r -- ""
}

###############################################################################
# Timing Helpers
###############################################################################

bench_adjust_iters() {
  emulate -L zsh
  setopt localoptions no_unset

  local -i base="$1"
  local -i adjusted="$base"

  if (( BENCH_QUICK )); then
    adjusted=$(( base / 5 ))
    (( adjusted < 20 )) && adjusted=20
  fi

  REPLY="$adjusted"
}

bench_sort_numbers() {
  emulate -L zsh
  setopt localoptions

  local -a sorted=("$@")
  local -i i j n=${#sorted}
  local tmp
  local -F a b

  for (( i = 1; i <= n; i++ )); do
    for (( j = i + 1; j <= n; j++ )); do
      a="${sorted[i]}"
      b="${sorted[j]}"
      if (( b < a )); then
        tmp="${sorted[i]}"
        sorted[i]="${sorted[j]}"
        sorted[j]="$tmp"
      fi
    done
  done

  reply=("${sorted[@]}")
}

bench_stats() {
  emulate -L zsh
  setopt localoptions

  local -a sorted
  bench_sort_numbers "$@"
  sorted=("${reply[@]}")

  local -i n=${#sorted}
  local -F sum=0 value min max mean median

  if (( n == 0 )); then
    reply=(0 0 0 0)
    return 0
  fi

  for value in "${sorted[@]}"; do
    (( sum += value ))
  done

  min="${sorted[1]}"
  max="${sorted[-1]}"
  mean=$(( sum / n ))

  if (( n % 2 == 1 )); then
    median="${sorted[$(((n + 1) / 2))]}"
  else
    median=$(( (sorted[$((n / 2))] + sorted[$((n / 2 + 1))]) / 2.0 ))
  fi

  reply=("$min" "$median" "$mean" "$max")
}

bench_time_once() {
  emulate -L zsh
  setopt localoptions

  local -i iters="$1"
  shift

  local -i warmup=$(( iters / 20 ))
  (( warmup < 1 )) && warmup=1
  (( warmup > 200 )) && warmup=200

  local -i i

  {
    for (( i = 0; i < warmup; i++ )); do
      "$@"
    done
  } >/dev/null 2>&1

  local -F start end elapsed_ms
  start="$EPOCHREALTIME"

  {
    for (( i = 0; i < iters; i++ )); do
      "$@"
    done
  } >/dev/null 2>&1

  end="$EPOCHREALTIME"
  elapsed_ms=$(( (end - start) * 1000.0 ))

  (( elapsed_ms < 0 )) && elapsed_ms=0

  REPLY="$elapsed_ms"
}
bench_csv_escape() {
  emulate -L zsh
  setopt localoptions no_unset

  local value="${1-}"
  value="${value//\"/\"\"}"
  REPLY="\"${value}\""
}

bench_should_run() {
  emulate -L zsh
  setopt localoptions no_unset

  local group="$1"
  local label="$2"

  [[ -z "$BENCH_FILTER" ]] && return 0
  [[ "$group" == *"$BENCH_FILTER"* || "$label" == *"$BENCH_FILTER"* ]]
}

bench_section() {
  emulate -L zsh
  setopt localoptions no_unset

  print -r -- ""
  print -r -- "━━━ $1 ━━━"
  printf "  %-16s %-42s %9s %11s %12s %12s\n" \
    "Group" "Case" "Iters" "Median ms" "µs/op" "Ops/sec"
}

bench_case() {
  emulate -L zsh
  setopt localoptions no_unset

  local group="$1"
  local label="$2"
  local -i base_iters="$3"
  shift 3

  bench_should_run "$group" "$label" || return 0

  bench_adjust_iters "$base_iters"
  local -i iters="$REPLY"

  local -a samples=()
  local -i round
  for (( round = 1; round <= BENCH_ROUNDS; round++ )); do
    bench_time_once "$iters" "$@"
    samples+=("$REPLY")
  done

  bench_stats "${samples[@]}"
  local -F min_ms="${reply[1]}"
  local -F median_ms="${reply[2]}"
  local -F mean_ms="${reply[3]}"
  local -F max_ms="${reply[4]}"
  local -F per_op_us=0
  local -F ops_sec=0

  if (( median_ms > 0 )); then
    per_op_us=$(( median_ms * 1000.0 / iters ))
    ops_sec=$(( iters * 1000.0 / median_ms ))
  fi

  local id="${group}:${label}"
  BENCH_ORDER+=("$id")
  BENCH_GROUP[$id]="$group"
  BENCH_LABEL[$id]="$label"
  BENCH_ITERS[$id]="$iters"
  BENCH_MIN_MS[$id]="$min_ms"
  BENCH_MEDIAN_MS[$id]="$median_ms"
  BENCH_MEAN_MS[$id]="$mean_ms"
  BENCH_MAX_MS[$id]="$max_ms"
  BENCH_PER_OP_US[$id]="$per_op_us"
  BENCH_OPS_SEC[$id]="$ops_sec"

  printf "  %-16s %-42s %9d %11.3f %12.3f %12.0f\n" \
    "$group" "$label" "$iters" "$median_ms" "$per_op_us" "$ops_sec"

  if [[ -n "$BENCH_CSV" ]]; then
    local csv_group csv_label
    bench_csv_escape "$group"
    csv_group="$REPLY"
    bench_csv_escape "$label"
    csv_label="$REPLY"

    printf "%s,%s,%d,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n" \
      "$csv_group" "$csv_label" "$iters" "$BENCH_ROUNDS" \
      "$min_ms" "$median_ms" "$mean_ms" "$max_ms" "$per_op_us" "$ops_sec" >> "$BENCH_CSV"
  fi
}

###############################################################################
# Benchmark Commands
###############################################################################

bench_noop() {
  :
}

bench_context_create_remove() {
  z::log::with_context request_id req-001 user alice >/dev/null 2>&1
  local ctx="$REPLY"
  [[ -n "$ctx" ]] && z::log::remove_context "$ctx" >/dev/null 2>&1
}

bench_log_and_flush() {
  z::log::info "Buffered flush message" key value >/dev/null 2>&1
  z::log::flush >/dev/null 2>&1
}

###############################################################################
# Scenario Groups
###############################################################################

bench_baseline() {
  bench_section "Baseline"
  bench_case "baseline" "noop function call" 100000 bench_noop
}

bench_json() {
  bench_section "JSON Escaping"

  bench_case "json" "escape simple string" 50000 \
    __z::json::escape "simple text without special characters"

  bench_case "json" "escape quotes" 50000 \
    __z::json::escape 'text with "quoted" words'

  bench_case "json" "escape backslashes" 50000 \
    __z::json::escape 'path: C:\Users\test\file.txt'

  bench_case "json" "escape controls" 30000 \
    __z::json::escape $'line1\nline2\tTabbed\rCR'

  bench_case "json" "escape mixed complex" 30000 \
    __z::json::escape $'Error: "disk full" at C:\\tmp\n\tcode=28'

  bench_case "json" "escape 2KB clean string" 10000 \
    __z::json::escape "$BENCH_LARGE_STRING"
}

bench_levels() {
  bench_section "Level Helpers"

  z::log::reset >/dev/null 2>&1
  z::log::set_color_mode none >/dev/null 2>&1
  z::log::set_level info >/dev/null 2>&1

  bench_case "level" "level_name 2" 100000 __z::log::level_name 2
  bench_case "level" "level_number info" 100000 __z::log::level_number info
  bench_case "level" "is_level_active active" 100000 __z::log::is_level_active 2
  bench_case "level" "is_level_active inactive" 100000 __z::log::is_level_active 3
  bench_case "level" "if_info true" 100000 z::log::if_info
  bench_case "level" "if_debug false" 100000 z::log::if_debug
}

bench_timestamps() {
  bench_section "Timestamps"

  z::log::enable_timestamp_cache >/dev/null 2>&1
  bench_case "timestamp" "get_timestamp human cached" 50000 z::log::get_timestamp human
  bench_case "timestamp" "get_timestamp iso cached" 50000 z::log::get_timestamp iso
  bench_case "timestamp" "get_timestamp ms cached" 50000 z::log::get_timestamp ms
  bench_case "timestamp" "benchmark_now" 100000 z::log::benchmark_now

  z::log::disable_timestamp_cache >/dev/null 2>&1
  bench_case "timestamp" "get_timestamp human uncached" 5000 z::log::get_timestamp human

  z::log::enable_timestamp_cache >/dev/null 2>&1
}

bench_formatters() {
  bench_section "Formatters"

  z::log::reset >/dev/null 2>&1
  z::log::set_color_mode none >/dev/null 2>&1
  z::log::set_format text >/dev/null 2>&1

  bench_case "format" "format_text no fields" 10000 \
    __z::log::format_text 2 "Simple log message"

  bench_case "format" "format_text 2 fields" 10000 \
    __z::log::format_text 2 "Log message" key1 val1 key2 val2

  bench_case "format" "format_text 4 fields" 8000 \
    __z::log::format_text 2 "Log message" k1 v1 k2 v2 k3 v3 k4 v4

  bench_case "format" "format_simple text" 20000 \
    __z::log::format_simple 2 "Simple log message"

  z::log::set_format json >/dev/null 2>&1

  bench_case "format" "format_json no fields" 10000 \
    __z::log::format_json 2 "Simple log message"

  bench_case "format" "format_json 2 fields" 10000 \
    __z::log::format_json 2 "Log message" key1 val1 key2 val2

  bench_case "format" "format_simple json" 20000 \
    __z::log::format_simple 2 "Simple log message"
}

bench_logging() {
  bench_section "Public Logging"

  z::log::reset >/dev/null 2>&1
  z::log::set_color_mode none >/dev/null 2>&1
  z::log::setup "-" error text >/dev/null 2>&1
  bench_case "logging" "debug filtered console-only" 100000 \
    z::log::debug "Filtered debug"

  z::log::setup "-" debug text >/dev/null 2>&1
  bench_case "logging" "info console text no fields" 5000 \
    z::log::info "Console message"

  bench_case "logging" "info console text 2 fields" 5000 \
    z::log::info "Console message" key value

  local log_text="$BENCH_DIR/log-text.log"
  : > "$log_text"
  z::log::setup "$log_text" debug text >/dev/null 2>&1
  _zlog_config[rotate]=0
  bench_case "logging" "info file text unbuffered" 3000 \
    z::log::info "File message" key value

  local log_json="$BENCH_DIR/log-json.log"
  : > "$log_json"
  z::log::setup "$log_json" debug json >/dev/null 2>&1
  _zlog_config[rotate]=0
  bench_case "logging" "info file json unbuffered" 3000 \
    z::log::info "JSON file message" key value

  local log_buf="$BENCH_DIR/log-buffered.log"
  : > "$log_buf"
  z::log::setup "$log_buf" debug text >/dev/null 2>&1
  _zlog_config[rotate]=0
  z::log::enable_buffering 1000 >/dev/null 2>&1
  bench_case "logging" "info file text buffered" 10000 \
    z::log::info "Buffered message" key value
  z::log::flush >/dev/null 2>&1
  bench_case "logging" "info buffered plus flush each op" 1000 \
    bench_log_and_flush
  z::log::disable_buffering >/dev/null 2>&1
}

bench_contexts() {
  bench_section "Context Loggers"

  local log="$BENCH_DIR/context.log"
  : > "$log"
  z::log::reset >/dev/null 2>&1
  z::log::set_color_mode none >/dev/null 2>&1
  z::log::setup "$log" debug text >/dev/null 2>&1
  _zlog_config[rotate]=0

  bench_case "context" "with_context create+remove" 2000 \
    bench_context_create_remove

  z::log::with_context request_id req-bench user_id bench >/dev/null 2>&1
  BENCH_CTX="$REPLY"
  if [[ -z "$BENCH_CTX" ]]; then
    print -r -u2 -- "benchmark-zlog: failed to create benchmark context; skipping context-call cases"
    return 1
  fi
  BENCH_CTX_INFO="${BENCH_CTX}::info"
  bench_case "context" "direct info same fields" 3000 \
  z::log::info "Context log message" request_id req-bench user_id bench

  bench_case "context" "ctx info inherited fields" 3000 \
    "$BENCH_CTX_INFO" "Context log message"

  bench_case "context" "ctx info inherited+extra fields" 3000 \
    "$BENCH_CTX_INFO" "Context log message" extra_key extra_val

  z::log::remove_context "$BENCH_CTX" >/dev/null 2>&1
  BENCH_CTX=""
  BENCH_CTX_INFO=""
}

bench_rotation() {
  bench_section "File Size & Rotation"

  local log="$BENCH_DIR/rotate.log"
  print -r -- "abcdef" > "$log"

  z::log::reset >/dev/null 2>&1
  z::log::set_file "$log" >/dev/null 2>&1
  _zlog_config[rotate]=1
  _zlog_config[rotate_size]=1048576
  _zlog_config[rotate_keep]=2

  bench_case "rotation" "get_file_size" 10000 \
    __z::log::get_file_size "$log"

  bench_case "rotation" "rotate_if_needed no-op" 3000 \
    __z::log::rotate_if_needed
}

bench_performance_mode() {
  bench_section "Performance Mode"

  local log="$BENCH_DIR/performance.log"
  : > "$log"

  z::log::reset >/dev/null 2>&1
  z::log::set_color_mode none >/dev/null 2>&1
  z::log::setup "$log" debug text >/dev/null 2>&1
  _zlog_config[rotate]=0

  z::log::disable_performance_mode >/dev/null 2>&1 || true
  bench_case "perf" "normal info file no fields" 5000 \
    z::log::info "Normal mode message"

  bench_case "perf" "normal info file 2 fields" 5000 \
    z::log::info "Normal mode message" key value

  z::log::enable_performance_mode >/dev/null 2>&1
  bench_case "perf" "fast info file no fields" 5000 \
    z::log::info "Performance mode message"

  bench_case "perf" "fast info file 2 fields" 5000 \
    z::log::info "Performance mode message" key value

  z::log::disable_performance_mode >/dev/null 2>&1
}

bench_async() {
  (( BENCH_INCLUDE_ASYNC )) || return 0

  bench_section "Async Logging"

  local log="$BENCH_DIR/async.log"
  : > "$log"

  z::log::reset >/dev/null 2>&1
  z::log::set_color_mode none >/dev/null 2>&1
  z::log::setup "$log" debug text >/dev/null 2>&1
  _zlog_config[rotate]=0

  if ! z::log::enable_async >/dev/null 2>&1; then
    print -r -- "  async           skipped: enable_async failed"
    return 0
  fi

  bench_case "async" "info file async" 5000 \
    z::log::info "Async message" key value

  z::log::disable_async >/dev/null 2>&1 || true
}

###############################################################################
# Summary
###############################################################################

bench_print_summary() {
  emulate -L zsh
  setopt localoptions

  print -r -- ""
  print -r -- "╔════════════════════════════════════════════════════════════════╗"
  print -r -- "║                         Summary                              ║"
  print -r -- "╚════════════════════════════════════════════════════════════════╝"

  if (( ${#BENCH_ORDER} == 0 )); then
    print -r -- "  No benchmark cases matched."
    return 0
  fi

  printf "  %-16s %-42s %12s %12s %12s %12s\n" \
    "Group" "Case" "min ms" "median ms" "mean ms" "max ms"

  local id
  for id in "${BENCH_ORDER[@]}"; do
    printf "  %-16s %-42s %12.3f %12.3f %12.3f %12.3f\n" \
      "${BENCH_GROUP[$id]}" \
      "${BENCH_LABEL[$id]}" \
      "${BENCH_MIN_MS[$id]}" \
      "${BENCH_MEDIAN_MS[$id]}" \
      "${BENCH_MEAN_MS[$id]}" \
      "${BENCH_MAX_MS[$id]}"
  done

  print -r -- ""
  print -r -- "  Notes:"
  print -r -- "  * Use median ms and µs/op for comparisons."
  print -r -- "  * Run on an idle machine for release numbers."
  print -r -- "  * Use --quick for smoke checks, not published results."
  print -r -- "  * Use --include-async only when FIFO behavior is stable in the environment."

  if [[ -n "$BENCH_CSV" ]]; then
    print -r -- ""
    print -r -- "  CSV written to: $BENCH_CSV"
  fi
}

###############################################################################
# Main
###############################################################################

bench_main() {
  emulate -L zsh
  setopt localoptions

  bench_parse_args "$@"
  local parse_rc=$?
  if (( parse_rc == 99 )); then
    return 0
  elif (( parse_rc != 0 )); then
    return "$parse_rc"
  fi

  bench_make_dir || return 1

  {
    bench_setup

    bench_baseline
    bench_json
    bench_levels
    bench_timestamps
    bench_formatters
    bench_logging
    bench_contexts
    bench_rotation
    bench_performance_mode
    bench_async

    bench_print_summary
  } always {
    bench_cleanup
  }

  return 0
}

if [[ "${ZSH_EVAL_CONTEXT:-}" == "toplevel" ]]; then
  bench_main "$@"
  exit $?
fi
