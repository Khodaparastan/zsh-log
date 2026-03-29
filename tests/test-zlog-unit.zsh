#!/usr/bin/env zsh
# ==============================================================================
#  zlog — Unit Test Suite
#  Tests internal functions, globals, and low-level subsystems.
#  Run from the repo root: zsh tests/test-zlog-unit.zsh
# ==============================================================================

emulate -L zsh
setopt err_return no_unset pipe_fail

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/../zlog"

###############################################################################
# Minimal test framework
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
  __z::log::validate_globals
  assert_eq "$_ZLOG_MIN_ROTATE_SIZE" "${_zlog_config[rotate_size]}" \
    "rotate_size < min clamped to min"

  _zlog_config[rotate_size]=2000000000
  __z::log::validate_globals
  assert_eq "$_ZLOG_MAX_ROTATE_SIZE" "${_zlog_config[rotate_size]}" \
    "rotate_size > max clamped to max"

  _zlog_config[buffer_max]=0
  __z::log::validate_globals
  assert_eq "$_ZLOG_MIN_BUFFER_SIZE" "${_zlog_config[buffer_max]}" \
    "buffer_max < min clamped to min"

  _zlog_config[buffer_max]=20000
  __z::log::validate_globals
  assert_eq "$_ZLOG_MAX_BUFFER_SIZE" "${_zlog_config[buffer_max]}" \
    "buffer_max > max clamped to max"

  _zlog_config[level]=-1
  __z::log::validate_globals
  assert_eq "2" "${_zlog_config[level]}" "Invalid level -1 reset to INFO (2)"

  _zlog_config[level]=10
  __z::log::validate_globals
  assert_eq "2" "${_zlog_config[level]}" "Invalid level 10 reset to INFO (2)"

  _zlog_config[file_level]=10
  __z::log::validate_globals
  assert_eq "-1" "${_zlog_config[file_level]}" "Invalid file_level reset to -1"

  _zlog_config[rotate_keep]=-5
  __z::log::validate_globals
  assert_eq "0" "${_zlog_config[rotate_keep]}" "rotate_keep < 0 clamped to 0"

  _zlog_config[rotate_keep]=200
  __z::log::validate_globals
  assert_eq "100" "${_zlog_config[rotate_keep]}" "rotate_keep > 100 clamped to 100"

  _zlog_config[rotation_lock_timeout]=0
  __z::log::validate_globals
  assert_eq "1" "${_zlog_config[rotation_lock_timeout]}" "lock_timeout < 1 clamped to 1"

  _zlog_config[rotation_lock_timeout]=100
  __z::log::validate_globals
  assert_eq "60" "${_zlog_config[rotation_lock_timeout]}" "lock_timeout > 60 clamped to 60"

  _zlog_config[max_depth]=0
  __z::log::validate_globals
  assert_eq "1" "${_zlog_config[max_depth]}" "max_depth < 1 clamped to 1"

  _zlog_config[max_depth]=50
  __z::log::validate_globals
  assert_eq "20" "${_zlog_config[max_depth]}" "max_depth > 20 clamped to 20"

  # Restore
  _zlog_config[rotate_size]=$orig_rotate_size
  _zlog_config[buffer_max]=$orig_buffer_max
  _zlog_config[level]=$orig_level
  __z::log::validate_globals
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
  __z::log::detect_color_support
  assert_eq "none" "$REPLY" "NO_COLOR=1 → none"
  unset NO_COLOR

  TERM=dumb
  __z::log::detect_color_support
  assert_eq "none" "$REPLY" "TERM=dumb → none"

  # When stderr is not a tty the function returns "none" for all other TERMs.
  # Verify the function always returns a known value (not empty).
  TERM=xterm-256color; unset COLORTERM
  __z::log::detect_color_support
  assert_ne "" "$REPLY" "detect_color_support always returns a non-empty value"
}

###############################################################################
# 4. RGB → 256 Color Conversion
###############################################################################

test_rgb_to_256() {
  section "RGB → 256 Color Conversion"

  __z::log::rgb_to_256 0 0 0;       assert_eq "16"  "$REPLY" "Black (0,0,0) → 16"
  __z::log::rgb_to_256 255 255 255; assert_eq "231" "$REPLY" "White (255,255,255) → 231"
  __z::log::rgb_to_256 255 0 0;     assert_eq "196" "$REPLY" "Red (255,0,0) → 196"
  __z::log::rgb_to_256 0 255 0;     assert_eq "46"  "$REPLY" "Green (0,255,0) → 46"
  __z::log::rgb_to_256 0 0 255;     assert_eq "21"  "$REPLY" "Blue (0,0,255) → 21"
  __z::log::rgb_to_256 128 128 128; assert_eq "244" "$REPLY" "Gray (128,128,128) → 244"

  local rc
  __z::log::rgb_to_256 256 0 0 2>/dev/null; rc=$?
  assert_rc 1 $rc "RGB > 255 fails"

  __z::log::rgb_to_256 -1 0 0 2>/dev/null; rc=$?
  assert_rc 1 $rc "Negative RGB fails"

  __z::log::rgb_to_256 abc 0 0 2>/dev/null; rc=$?
  assert_rc 1 $rc "Non-numeric RGB fails"

  __z::log::rgb_to_256 100 200 2>/dev/null; rc=$?
  assert_rc 1 $rc "Missing third arg fails"
}

###############################################################################
# 5. Color Initialization & Mode Management
###############################################################################

test_color_system() {
  section "Color System"

  # Trigger lazy initialization
  z::log::get_color_mode &>/dev/null

  assert_eq "1"  "${_zlog_color_cache[initialized]}" "Colors initialized after first use"
  assert_ne ""   "${_zlog_color_cache[mode]}"        "Color mode is set"
  assert_ne "auto" "${_zlog_color_cache[mode]}"      "Color mode resolved from 'auto'"

  local orig_mode="${_zlog_color_cache[mode]}"

  z::log::set_color_mode "none";      assert_eq "none"      "${_zlog_color_cache[mode]}" "set_color_mode none"
  z::log::set_color_mode "basic";     assert_eq "basic"     "${_zlog_color_cache[mode]}" "set_color_mode basic"
  z::log::set_color_mode "256";       assert_eq "256"       "${_zlog_color_cache[mode]}" "set_color_mode 256"
  z::log::set_color_mode "truecolor"; assert_eq "truecolor" "${_zlog_color_cache[mode]}" "set_color_mode truecolor"

  local mode; mode=$(z::log::get_color_mode)
  assert_eq "truecolor" "$mode" "get_color_mode returns current mode"

  local rc
  z::log::set_color_mode "invalid" 2>/dev/null; rc=$?
  assert_rc 1 $rc "Invalid color mode returns 1"

  z::log::set_color_mode "$orig_mode"
}

###############################################################################
# 6. Colorize Function
###############################################################################

test_colorize() {
  section "Colorize Function"

  z::log::colorize "red" "Error text"
  assert_contains "$REPLY" "Error text" "Colorized text contains original"

  z::log::colorize "error" "Error text"
  assert_contains "$REPLY" "Error text" "Semantic color 'error' works"

  z::log::colorize "rgb(255, 0, 0)" "Red text"
  assert_contains "$REPLY" "Red text" "RGB color works"

  z::log::colorize "rgb(300,0,0)" "Invalid"
  assert_eq "Invalid" "$REPLY" "Invalid RGB returns plain text"

  z::log::colorize "nonexistent_color" "Plain"
  assert_eq "Plain" "$REPLY" "Unknown color name returns plain text"
}

###############################################################################
# 7. Internal Debug Mode
###############################################################################

test_debug_mode() {
  section "Internal Debug Mode"

  assert_eq "0" "${_zlog_config[debug_mode]}" "debug_mode off by default"

  z::log::enable_debug_mode
  assert_eq "1" "${_zlog_config[debug_mode]}" "enable_debug_mode sets flag"

  z::log::is_debug_mode
  assert_rc 0 $? "is_debug_mode returns 0 when enabled"

  local out
  out=$(__z::log::debug_internal "Test message" 2>&1)
  assert_contains "$out" "zlog[DEBUG]" "debug_internal output has prefix"
  assert_contains "$out" "Test message" "debug_internal output has message"

  z::log::disable_debug_mode
  assert_eq "0" "${_zlog_config[debug_mode]}" "disable_debug_mode clears flag"

  z::log::is_debug_mode
  assert_rc 1 $? "is_debug_mode returns 1 when disabled"

  out=$(__z::log::debug_internal "Should not appear" 2>&1)
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
  z::log::set_level info

  __z::log::level_name 0; assert_eq "ERROR" "$REPLY" "level_name 0 = ERROR"
  __z::log::level_name 1; assert_eq "WARN"  "$REPLY" "level_name 1 = WARN"
  __z::log::level_name 2; assert_eq "INFO"  "$REPLY" "level_name 2 = INFO"
  __z::log::level_name 3; assert_eq "DEBUG" "$REPLY" "level_name 3 = DEBUG"

  __z::log::level_number "error"; assert_eq "0" "$REPLY" "level_number error = 0"
  __z::log::level_number "warn";  assert_eq "1" "$REPLY" "level_number warn = 1"
  __z::log::level_number "info";  assert_eq "2" "$REPLY" "level_number info = 2"
  __z::log::level_number "debug"; assert_eq "3" "$REPLY" "level_number debug = 3"
  __z::log::level_number "INFO";  assert_eq "2" "$REPLY" "level_number INFO (uppercase) = 2"

  __z::log::is_level_active 0; assert_rc 0 $? "ERROR active at info level"
  __z::log::is_level_active 1; assert_rc 0 $? "WARN active at info level"
  __z::log::is_level_active 2; assert_rc 0 $? "INFO active at info level"
  __z::log::is_level_active 3; assert_rc 1 $? "DEBUG inactive at info level"

  z::log::if_error; assert_rc 0 $? "if_error true at info level"
  z::log::if_warn;  assert_rc 0 $? "if_warn true at info level"
  z::log::if_info;  assert_rc 0 $? "if_info true at info level"
  z::log::if_debug; assert_rc 1 $? "if_debug false at info level"

  _zlog_config[level]=$orig_level
}

###############################################################################
# 10. show_colors output
###############################################################################

test_show_colors() {
  section "show_colors Output"

  local out
  out=$(z::log::show_colors 2>&1)
  local rc=$?
  assert_rc 0 $rc "show_colors exits 0"
  assert_contains "$out" "Color Mode:"       "Output has Color Mode section"
  assert_contains "$out" "Basic Colors:"     "Output has Basic Colors section"
  assert_contains "$out" "Log Level Colors:" "Output has Log Level Colors section"
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

summary
