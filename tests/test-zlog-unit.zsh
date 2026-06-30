#!/usr/bin/env zsh
# ==============================================================================
#  zlog — Unit Test Suite
#  Tests internal functions, globals, and low-level subsystems.
#  Run from the repo root: zsh tests/test-zlog-unit.zsh
# ==============================================================================

emulate -L zsh
setopt no_unset pipe_fail

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/../zlog"

###############################################################################
# Minimal test framework
###############################################################################

typeset -gi _t_count=0 _t_passed=0 _t_failed=0
typeset -ga _t_failures=()

_t_ok() {
  local desc="$1"
  (( ++_t_count )); (( ++_t_passed ))
  print "  ✓ $desc"
}

_t_fail() {
  local desc="$1" detail="${2:-}"
  (( ++_t_count )); (( ++_t_failed ))
  _t_failures+=("$desc")
  print "  ✗ $desc"
  [[ -n "$detail" ]] && print "    $detail"
}

assert_eq() {
  local expected="$1" actual="$2" desc="$3"
  if [[ "$actual" == "$expected" ]]; then
    _t_ok "$desc"
  else
    _t_fail "$desc" "expected='$expected' actual='$actual'"
  fi
}

assert_ne() {
  local not_expected="$1" actual="$2" desc="$3"
  if [[ "$actual" != "$not_expected" ]]; then
    _t_ok "$desc"
  else
    _t_fail "$desc" "should not equal '$not_expected'"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" desc="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    _t_ok "$desc"
  else
    _t_fail "$desc" "string='$haystack' missing='$needle'"
  fi
}

assert_rc() {
  local expected_rc="$1" actual_rc="$2" desc="$3"
  if (( actual_rc == expected_rc )); then
    _t_ok "$desc"
  else
    _t_fail "$desc" "expected rc=$expected_rc actual rc=$actual_rc"
  fi
}

section() { print "\n── $1 ──────────────────────────────────────────────────────" }

summary() {
  print "\n╔════════════════════════════════════════════════════════════════╗"
  print "║                    UNIT TEST RESULTS                          ║"
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

###############################################################################
# 1. Globals & Constants
###############################################################################

test_globals() {
  section "Globals & Constants"

  assert_eq "1"            "$_zlog_initialized"              "Initialized flag is 1"
  assert_eq "0"            "$_ZLOG_LEVEL_ERROR"              "ERROR level = 0"
  assert_eq "1"            "$_ZLOG_LEVEL_WARN"               "WARN level = 1"
  assert_eq "2"            "$_ZLOG_LEVEL_INFO"               "INFO level = 2"
  assert_eq "3"            "$_ZLOG_LEVEL_DEBUG"              "DEBUG level = 3"
  assert_eq "ERROR"        "${_ZLOG_LEVEL_NAMES[0]}"         "Level name 0 = ERROR"
  assert_eq "WARN"         "${_ZLOG_LEVEL_NAMES[1]}"         "Level name 1 = WARN"
  assert_eq "INFO"         "${_ZLOG_LEVEL_NAMES[2]}"         "Level name 2 = INFO"
  assert_eq "DEBUG"        "${_ZLOG_LEVEL_NAMES[3]}"         "Level name 3 = DEBUG"
  assert_eq "1024"         "$_ZLOG_MIN_ROTATE_SIZE"          "Min rotate size = 1KB"
  assert_eq "1073741824"   "$_ZLOG_MAX_ROTATE_SIZE"          "Max rotate size = 1GB"
  assert_eq "1"            "$_ZLOG_MIN_BUFFER_SIZE"          "Min buffer size = 1"
  assert_eq "10000"        "$_ZLOG_MAX_BUFFER_SIZE"          "Max buffer size = 10000"

  assert_eq "text"         "${_zlog_config[format]}"         "Default format = text"
  assert_eq ""             "${_zlog_config[file]}"           "Default file = empty"
  assert_eq "-1"           "${_zlog_config[file_level]}"     "Default file_level = -1"
  assert_eq "1"            "${_zlog_config[rotate]}"         "Rotation enabled by default"
  assert_eq "10485760"     "${_zlog_config[rotate_size]}"    "Default rotate_size = 10MB"
  assert_eq "5"            "${_zlog_config[rotate_keep]}"    "Default rotate_keep = 5"
  assert_eq "0"            "${_zlog_config[buffered]}"       "Buffering disabled by default"
  assert_eq "50"           "${_zlog_config[buffer_max]}"     "Default buffer_max = 50"
  assert_eq "0"            "${_zlog_config[debug_mode]}"     "debug_mode = 0 by default"

  assert_eq "0"            "${_zlog_stats[messages_logged]}" "Stats: messages_logged starts at 0"
}

###############################################################################
# 2. Configuration Validation
###############################################################################

test_validation() {
  section "Configuration Validation"

  local orig_rotate_size="${_zlog_config[rotate_size]}"
  local orig_buffer_max="${_zlog_config[buffer_max]}"
  local orig_level="${_zlog_config[level]}"

  _zlog_config[rotate_size]=100
  __zlog::validate_globals
  assert_eq "$_ZLOG_MIN_ROTATE_SIZE" "${_zlog_config[rotate_size]}" \
    "rotate_size < min clamped to min"

  _zlog_config[rotate_size]=2000000000
  __zlog::validate_globals
  assert_eq "$_ZLOG_MAX_ROTATE_SIZE" "${_zlog_config[rotate_size]}" \
    "rotate_size > max clamped to max"

  _zlog_config[buffer_max]=0
  __zlog::validate_globals
  assert_eq "$_ZLOG_MIN_BUFFER_SIZE" "${_zlog_config[buffer_max]}" \
    "buffer_max < min clamped to min"

  _zlog_config[buffer_max]=20000
  __zlog::validate_globals
  assert_eq "$_ZLOG_MAX_BUFFER_SIZE" "${_zlog_config[buffer_max]}" \
    "buffer_max > max clamped to max"

  _zlog_config[level]=-1
  __zlog::validate_globals
  assert_eq "2" "${_zlog_config[level]}" "Invalid level -1 reset to INFO (2)"

  _zlog_config[level]=10
  __zlog::validate_globals
  assert_eq "2" "${_zlog_config[level]}" "Invalid level 10 reset to INFO (2)"

  _zlog_config[file_level]=10
  __zlog::validate_globals
  assert_eq "-1" "${_zlog_config[file_level]}" "Invalid file_level reset to -1"

  _zlog_config[rotate_keep]=-5
  __zlog::validate_globals
  assert_eq "0" "${_zlog_config[rotate_keep]}" "rotate_keep < 0 clamped to 0"

  _zlog_config[rotate_keep]=200
  __zlog::validate_globals
  assert_eq "100" "${_zlog_config[rotate_keep]}" "rotate_keep > 100 clamped to 100"

  _zlog_config[rotation_lock_timeout]=0
  __zlog::validate_globals
  assert_eq "1" "${_zlog_config[rotation_lock_timeout]}" "lock_timeout < 1 clamped to 1"

  _zlog_config[rotation_lock_timeout]=100
  __zlog::validate_globals
  assert_eq "60" "${_zlog_config[rotation_lock_timeout]}" "lock_timeout > 60 clamped to 60"

  _zlog_config[max_depth]=0
  __zlog::validate_globals
  assert_eq "1" "${_zlog_config[max_depth]}" "max_depth < 1 clamped to 1"

  _zlog_config[max_depth]=50
  __zlog::validate_globals
  assert_eq "20" "${_zlog_config[max_depth]}" "max_depth > 20 clamped to 20"

  # Restore
  _zlog_config[rotate_size]=$orig_rotate_size
  _zlog_config[buffer_max]=$orig_buffer_max
  _zlog_config[level]=$orig_level
  __zlog::validate_globals
}

###############################################################################
# 3. Color Detection
###############################################################################

test_color_detection() {
  section "Color Detection"

  # Note: detect_color_support checks [[ -t 2 ]] (stderr is a tty).
  # In a non-interactive test environment stderr is not a tty, so only
  # the early-exit cases (NO_COLOR, TERM=dumb) are reliably testable.

  local -x NO_COLOR TERM COLORTERM

  NO_COLOR=1
  __zlog::detect_color_support
  assert_eq "none" "$REPLY" "NO_COLOR=1 → none"
  unset NO_COLOR

  TERM=dumb
  __zlog::detect_color_support
  assert_eq "none" "$REPLY" "TERM=dumb → none"

  # When stderr is not a tty the function returns "none" for all other TERMs.
  # Verify the function always returns a known value (not empty).
  TERM=xterm-256color; unset COLORTERM
  __zlog::detect_color_support
  assert_ne "" "$REPLY" "detect_color_support always returns a non-empty value"
}

###############################################################################
# 4. RGB → 256 Color Conversion
###############################################################################

test_rgb_to_256() {
  section "RGB → 256 Color Conversion"

  __zlog::rgb_to_256 0 0 0;       assert_eq "16"  "$REPLY" "Black (0,0,0) → 16"
  __zlog::rgb_to_256 255 255 255; assert_eq "231" "$REPLY" "White (255,255,255) → 231"
  __zlog::rgb_to_256 255 0 0;     assert_eq "196" "$REPLY" "Red (255,0,0) → 196"
  __zlog::rgb_to_256 0 255 0;     assert_eq "46"  "$REPLY" "Green (0,255,0) → 46"
  __zlog::rgb_to_256 0 0 255;     assert_eq "21"  "$REPLY" "Blue (0,0,255) → 21"
  __zlog::rgb_to_256 128 128 128; assert_eq "244" "$REPLY" "Gray (128,128,128) → 244"

  local rc
  __zlog::rgb_to_256 256 0 0 2>/dev/null; rc=$?
  assert_rc 1 $rc "RGB > 255 fails"

  __zlog::rgb_to_256 -1 0 0 2>/dev/null; rc=$?
  assert_rc 1 $rc "Negative RGB fails"

  __zlog::rgb_to_256 abc 0 0 2>/dev/null; rc=$?
  assert_rc 1 $rc "Non-numeric RGB fails"

  __zlog::rgb_to_256 100 200 2>/dev/null; rc=$?
  assert_rc 1 $rc "Missing third arg fails"
}

###############################################################################
# 5. Color Initialization & Mode Management
###############################################################################

test_color_system() {
  section "Color System"

  # Trigger lazy initialization
  zlog::get_color_mode &>/dev/null

  assert_eq "1"  "${_zlog_color_cache[initialized]}" "Colors initialized after first use"
  assert_ne ""   "${_zlog_color_cache[mode]}"        "Color mode is set"
  assert_ne "auto" "${_zlog_color_cache[mode]}"      "Color mode resolved from 'auto'"

  local orig_mode="${_zlog_color_cache[mode]}"

  zlog::set_color_mode "none";      assert_eq "none"      "${_zlog_color_cache[mode]}" "set_color_mode none"
  zlog::set_color_mode "basic";     assert_eq "basic"     "${_zlog_color_cache[mode]}" "set_color_mode basic"
  zlog::set_color_mode "256";       assert_eq "256"       "${_zlog_color_cache[mode]}" "set_color_mode 256"
  zlog::set_color_mode "truecolor"; assert_eq "truecolor" "${_zlog_color_cache[mode]}" "set_color_mode truecolor"

  local mode; mode=$(zlog::get_color_mode)
  assert_eq "truecolor" "$mode" "get_color_mode returns current mode"

  local rc
  zlog::set_color_mode "invalid" 2>/dev/null; rc=$?
  assert_rc 1 $rc "Invalid color mode returns 1"

  zlog::set_color_mode "$orig_mode"
}

###############################################################################
# 6. Colorize Function
###############################################################################

test_colorize() {
  section "Colorize Function"

  zlog::colorize "red" "Error text"
  assert_contains "$REPLY" "Error text" "Colorized text contains original"

  zlog::colorize "error" "Error text"
  assert_contains "$REPLY" "Error text" "Semantic color 'error' works"

  zlog::colorize "rgb(255, 0, 0)" "Red text"
  assert_contains "$REPLY" "Red text" "RGB color works"

  zlog::colorize "rgb(300,0,0)" "Invalid"
  assert_eq "Invalid" "$REPLY" "Invalid RGB returns plain text"

  zlog::colorize "nonexistent_color" "Plain"
  assert_eq "Plain" "$REPLY" "Unknown color name returns plain text"
}

###############################################################################
# 7. Internal Debug Mode
###############################################################################

test_debug_mode() {
  section "Internal Debug Mode"

  assert_eq "0" "${_zlog_config[debug_mode]}" "debug_mode off by default"

  zlog::enable_debug_mode
  assert_eq "1" "${_zlog_config[debug_mode]}" "enable_debug_mode sets flag"

  zlog::is_debug_mode
  assert_rc 0 $? "is_debug_mode returns 0 when enabled"

  local out
  out=$(__zlog::debug_internal "Test message" 2>&1)
  assert_contains "$out" "zlog[DEBUG]" "debug_internal output has prefix"
  assert_contains "$out" "Test message" "debug_internal output has message"

  zlog::disable_debug_mode
  assert_eq "0" "${_zlog_config[debug_mode]}" "disable_debug_mode clears flag"

  zlog::is_debug_mode
  assert_rc 1 $? "is_debug_mode returns 1 when disabled"

  out=$(__zlog::debug_internal "Should not appear" 2>&1)
  assert_eq "" "$out" "No debug output when disabled"
}

###############################################################################
# 8. JSON Escaping
###############################################################################

test_json_escaping() {
  section "JSON Escaping"

  __z::json::escape "simple text"
  assert_eq "simple text" "$REPLY" "Simple text unchanged"

  __z::json::escape 'text\with\backslash'
  assert_eq 'text\\with\\backslash' "$REPLY" "Backslashes escaped"

  __z::json::escape 'text "with" quotes'
  assert_eq 'text \"with\" quotes' "$REPLY" "Quotes escaped"

  __z::json::escape $'line1\nline2'
  assert_eq 'line1\nline2' "$REPLY" "Newline escaped"

  __z::json::escape $'text\twith\ttabs'
  assert_eq 'text\twith\ttabs' "$REPLY" "Tabs escaped"

  __z::json::escape $'text\rwith\rCR'
  assert_eq 'text\rwith\rCR' "$REPLY" "Carriage return escaped"

  __z::json::escape $'text\bwith\bBS'
  assert_eq 'text\bwith\bBS' "$REPLY" "Backspace escaped"

  __z::json::escape $'text\fwith\fFF'
  assert_eq 'text\fwith\fFF' "$REPLY" "Form feed escaped"

  __z::json::escape ""
  assert_eq "" "$REPLY" "Empty string unchanged"

  __z::json::escape "Hello 世界 🌍"
  assert_eq "Hello 世界 🌍" "$REPLY" "Unicode preserved"

  __z::json::escape $'line1\nline2\ttabbed\rCR'
  assert_eq 'line1\nline2\ttabbed\rCR' "$REPLY" "Multiple control chars escaped"
}

###############################################################################
# 9. Level Helpers
###############################################################################

test_level_helpers() {
  section "Level Helpers"

  local orig_level="${_zlog_config[level]}"
  zlog::set_level info

  __zlog::level_name 0; assert_eq "ERROR" "$REPLY" "level_name 0 = ERROR"
  __zlog::level_name 1; assert_eq "WARN"  "$REPLY" "level_name 1 = WARN"
  __zlog::level_name 2; assert_eq "INFO"  "$REPLY" "level_name 2 = INFO"
  __zlog::level_name 3; assert_eq "DEBUG" "$REPLY" "level_name 3 = DEBUG"

  __zlog::level_number "error"; assert_eq "0" "$REPLY" "level_number error = 0"
  __zlog::level_number "warn";  assert_eq "1" "$REPLY" "level_number warn = 1"
  __zlog::level_number "info";  assert_eq "2" "$REPLY" "level_number info = 2"
  __zlog::level_number "debug"; assert_eq "3" "$REPLY" "level_number debug = 3"
  __zlog::level_number "INFO";  assert_eq "2" "$REPLY" "level_number INFO (uppercase) = 2"

  __zlog::is_level_active 0; assert_rc 0 $? "ERROR active at info level"
  __zlog::is_level_active 1; assert_rc 0 $? "WARN active at info level"
  __zlog::is_level_active 2; assert_rc 0 $? "INFO active at info level"
  __zlog::is_level_active 3; assert_rc 1 $? "DEBUG inactive at info level"

  zlog::if_error; assert_rc 0 $? "if_error true at info level"
  zlog::if_warn;  assert_rc 0 $? "if_warn true at info level"
  zlog::if_info;  assert_rc 0 $? "if_info true at info level"
  zlog::if_debug; assert_rc 1 $? "if_debug false at info level"

  _zlog_config[level]=$orig_level
}

###############################################################################
# 10. show_colors output
###############################################################################

test_show_colors() {
  section "show_colors Output"

  local out
  out=$(zlog::show_colors 2>&1)
  local rc=$?
  assert_rc 0 $rc "show_colors exits 0"
  assert_contains "$out" "Color Mode:"       "Output has Color Mode section"
  assert_contains "$out" "Basic Colors:"     "Output has Basic Colors section"
  assert_contains "$out" "Log Level Colors:" "Output has Log Level Colors section"
}

###############################################################################
# 10b. format_text output (default engine formatter)
###############################################################################

# Pins the exact rendered structure of the default-engine text formatter.
# format_text was optimized to inline four cached-lookup helpers (level_name,
# sys::pid, the named-color path of colorize, and str::repeat padding) instead
# of calling them per log line; this test guards that the user-visible output
# is unchanged: 5-char level padding, UNKNOWN fallback, and context-field tail.
test_format_text() {
  section "format_text Output (default formatter)"

  local saved_mode; saved_mode=$(zlog::get_color_mode)
  local saved_format="${_zlog_config[format]}"
  zlog::set_color_mode none >/dev/null 2>&1
  _zlog_config[format]=text

  __zlog::format_text 0 "boom"
  assert_contains "$REPLY" " [ERROR] " "ERROR level not padded (5 chars already)"
  assert_contains "$REPLY" " boom"     "ERROR message present"

  __zlog::format_text 1 "careful"
  assert_contains "$REPLY" " [WARN ] " "WARN level padded to 5 chars"

  __zlog::format_text 2 "hello"
  assert_contains "$REPLY" " [INFO ] " "INFO level padded to 5 chars"

  __zlog::format_text 3 "trace"
  assert_contains "$REPLY" " [DEBUG] " "DEBUG level not padded (5 chars already)"

  __zlog::format_text 7 "weird"
  assert_contains "$REPLY" " [UNKNOWN] " "Unknown level falls back to UNKNOWN"

  __zlog::format_text 2 "with fields" request_id abc duration_ms 1500
  assert_contains "$REPLY" "request_id=abc"  "Context key=value rendered"
  assert_contains "$REPLY" "duration_ms=1500" "Second context key=value rendered"
  assert_contains "$REPLY" "| request_id"     "Context fields separated by pipe"

  __zlog::format_text 2 ""
  assert_rc 0 $? "Empty message is accepted"

  __zlog::format_text 2
  assert_rc 1 $? "Missing message returns 1"

  zlog::set_color_mode "$saved_mode" >/dev/null 2>&1
  _zlog_config[format]="$saved_format"
}

###############################################################################
# 10c. format_json output (default engine JSON formatter)
###############################################################################

# Pins the JSON formatter's structure and escaping. format_json was optimized to
# inline level/pid lookups, skip escaping the always-ASCII level name, and cache
# the escaped hostname/username (per-process constants) instead of re-escaping
# them on every line. This test guards that the rendered JSON is unchanged:
# correct field order, message/key/value escaping, and host/user re-escaping
# when the underlying value changes (cache invalidation via source marker).
test_format_json() {
  section "format_json Output (default JSON formatter)"

  local saved_format="${_zlog_config[format]}"
  _zlog_config[format]=json

  # Level name is rendered without escaping but must still be the right label.
  __zlog::format_json 0 "boom"
  assert_contains "$REPLY" '"level":"ERROR"'   "ERROR level label rendered"
  __zlog::format_json 2 "hello"
  assert_contains "$REPLY" '"level":"INFO"'    "INFO level label rendered"
  __zlog::format_json 7 "weird"
  assert_contains "$REPLY" '"level":"UNKNOWN"' "Unknown level falls back to UNKNOWN"

  # Required fixed fields are present.
  assert_contains "$REPLY" '"timestamp":"' "timestamp field present"
  assert_contains "$REPLY" '"hostname":"'  "hostname field present"
  assert_contains "$REPLY" '"pid":'        "pid field present (unquoted integer)"
  assert_contains "$REPLY" '"user":"'      "user field present"

  # Message escaping: quote and backslash must be escaped.
  __zlog::format_json 2 'a "q" \ b'
  assert_contains "$REPLY" '"message":"a \"q\" \\ b"' "Message quote/backslash escaped"

  # Context key/value pairs are appended and value-escaped.
  __zlog::format_json 2 "msg" k1 v1 k2 'v"2'
  assert_contains "$REPLY" '"k1":"v1"'   "Context key=value rendered"
  assert_contains "$REPLY" '"k2":"v\"2"' "Context value quote escaped"

  # Hostname with special chars must be escaped, then cached + reused.
  HOST=$'ho"st\\name'
  _zlog_sys_cache[hostname]=""
  _zlog_sys_cache[hostname_src]="__unset__"
  __zlog::format_json 2 "hello"
  assert_contains "$REPLY" '"hostname":"ho\"st\\name"' "Special hostname escaped in JSON"

  # Changing the hostname must invalidate the cached escape.
  HOST=$'second"host'
  _zlog_sys_cache[hostname]=""
  __zlog::format_json 2 "hello"
  assert_contains "$REPLY" '"hostname":"second\"host"' "Hostname re-escaped after change"

  # Odd/empty argument handling.
  __zlog::format_json 2 ""
  assert_rc 0 $? "Empty message accepted"
  __zlog::format_json 2
  assert_rc 1 $? "Missing message returns 1"

  zlog::clear_sys_cache all >/dev/null 2>&1
  _zlog_config[format]="$saved_format"
}

###############################################################################
# 11. Load Safety & Audit Regressions
###############################################################################

# Absolute path to the loader under test (resolve relative ../zlog).
typeset -g ZLOG_PATH="${SCRIPT_DIR}/../zlog"

# Regression guard for the audit's Critical/Major findings:
#   - sourcing must not mutate the caller shell's options (no file-scope emulate)
#   - re-sourcing must be clean (readonly constants guarded; "safe to source many times")
#   - __zlog::engine_fast must be defined exactly once (no shadowing duplicate)
#   - timestamp path must use the no-fork `strftime -s` assign form
#   - list_timers elapsed must be a real duration, never "<invalid>"
test_load_safety() {
  section "Load Safety & Audit Regressions"

  # (a) No option mutation of the parent shell when sourced.
  local opt_result
  opt_result=$(zsh -fc '
    before=$(setopt)
    source "$1" 2>/dev/null
    after=$(setopt)
    [[ "$before" == "$after" ]] && print MATCH || print DIFF
  ' zlog "$ZLOG_PATH")
  assert_eq "MATCH" "$opt_result" "Sourcing does not mutate caller shell options"

  # (b) Double-source is clean (no read-only variable errors on stderr).
  local dbl_err
  dbl_err=$(zsh -fc 'source "$1"; source "$1"' zlog "$ZLOG_PATH" 2>&1 >/dev/null)
  assert_eq "" "$dbl_err" "Re-sourcing produces no errors (no read-only variable)"

  # (c) engine_fast is defined exactly once (duplicate definition removed).
  local engine_def_count
  engine_def_count=$(grep -c '^__zlog::engine_fast()' "$ZLOG_PATH")
  assert_eq "1" "$engine_def_count" "__zlog::engine_fast defined exactly once"

  # (d) No $(strftime ...) command substitutions remain (use strftime -s instead).
  local strftime_subs
  strftime_subs=$(grep -c '\$(strftime' "$ZLOG_PATH")
  assert_eq "0" "$strftime_subs" "No \$(strftime) command substitutions remain"

  # (e) list_timers reports a valid elapsed duration (not "<invalid>").
  local orig_level="${_zlog_config[level]}"
  zlog::set_level debug
  zlog::clear_timers
  zlog::benchmark_start "audit-timer" >/dev/null
  local timers_out
  timers_out=$(zlog::list_timers)
  assert_contains "$timers_out" "audit-timer" "list_timers shows the timer name"
  local has_invalid=0
  [[ "$timers_out" == *"<invalid>"* ]] && has_invalid=1
  assert_eq "0" "$has_invalid" "list_timers elapsed is a real duration, not <invalid>"
  zlog::clear_timers
  _zlog_config[level]=$orig_level
  __zlog::update_fast_flags

  # (f) Public display helpers must emit context data literally. In particular,
  # values that look like print options or contain backslash escapes are data.
  zlog::remove_all_contexts
  zlog::with_context flag "-n" path 'C:\tmp\value' >/dev/null
  local contexts_out
  contexts_out=$(zlog::list_contexts)
  assert_contains "$contexts_out" "flag=-n" "list_contexts preserves option-like context value"
  assert_contains "$contexts_out" 'path=C:\tmp\value' "list_contexts preserves context backslashes"
  zlog::remove_all_contexts
}

###############################################################################
# Run all
###############################################################################

print "╔════════════════════════════════════════════════════════════════╗"
print "║                  zlog — Unit Test Suite                       ║"
print "╚════════════════════════════════════════════════════════════════╝"

test_globals
test_validation
test_color_detection
test_rgb_to_256
test_color_system
test_colorize
test_debug_mode
test_json_escaping
test_level_helpers
test_show_colors
test_format_text
test_format_json
test_load_safety

summary
