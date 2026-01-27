emulate -L zsh
setopt no_unset warn_create_global typeset_silent
zmodload zsh/datetime

typeset -gA _zcore_logging=(
  # Log levels
  [error]=0
  [warn]=1
  [info]=2
  [debug]=3

  # Current configuration
  [level]=2              # Default: info
  [format]="text"        # text or json
  [file]=""              # Empty = console only
  [file_level]=-1        # -1 = follow console level

  # File rotation
  [rotate_size]=10485760 # 10MB default
  [rotate_keep]=5        # Keep 5 old files

  # Performance settings
  [max_depth]=5          # Recursion protection
  [depth]=0              # Current recursion depth
  [buffered]=0           # Buffering disabled by default

  # Cache control
  [timestamp_cache_enabled]=1
)

# Buffering state
typeset -ga _zcore_log_buffer=()
typeset -gi _zcore_buffer_max=50
typeset -gi _zcore_buffer_count=0

# Timestamp cache
typeset -gi _timestamp_epoch=0
typeset -g _cached_timestamp=""
typeset -g _cached_iso_timestamp=""

# Context logging storage
typeset -gA _zcore_log_contexts=()
typeset -gA _zcore_log_contexts_parsed=()
typeset -gi _ZCORE_MAX_CONTEXTS=100
typeset -ga _zcore_log_contexts_order=()

# Context ID generation state
typeset -gi _zcore_context_counter=0

typeset -gA _zcore_benchmark_timers=()
typeset -gi _ZCORE_MAX_TIMERS=50
typeset -ga _zcore_benchmark_timer_order=()

# Level name mapping
typeset -gA _zcore_level_names=(
  [0]="ERROR"
  [1]="WARN"
  [2]="INFO"
  [3]="DEBUG"
)

typeset -gA _zcore_colors=(
  [reset]=""
  [bold]=""
  [dim]=""
  [blink]=""

  # Foreground colors
  [red]=""
  [green]=""
  [yellow]=""
  [blue]=""
  [magenta]=""
  [cyan]=""
  [white]=""
  [black]=""
)

__z::log::init_colors() {
  emulate -L zsh

  # Check if we should use colors
  if [[ ! -t 2 ]] || [[ -n ${NO_COLOR-} ]] || [[ ${TERM-} == "dumb" ]]; then
    return 0
  fi

  # Use tput if available, otherwise hardcode
  if command -v tput &>/dev/null && tput setaf 1 &>/dev/null; then
    _zcore_colors[reset]=$(tput sgr0 2>/dev/null)
    _zcore_colors[bold]=$(tput bold 2>/dev/null)
    _zcore_colors[dim]=$(tput dim 2>/dev/null)
    _zcore_colors[blink]=$(tput blink 2>/dev/null)

    _zcore_colors[black]=$(tput setaf 0 2>/dev/null)
    _zcore_colors[red]=$(tput setaf 1 2>/dev/null)
    _zcore_colors[green]=$(tput setaf 2 2>/dev/null)
    _zcore_colors[yellow]=$(tput setaf 3 2>/dev/null)
    _zcore_colors[blue]=$(tput setaf 4 2>/dev/null)
    _zcore_colors[magenta]=$(tput setaf 5 2>/dev/null)
    _zcore_colors[cyan]=$(tput setaf 6 2>/dev/null)
    _zcore_colors[white]=$(tput setaf 7 2>/dev/null)

  else
    # Fallback to ANSI codes
    _zcore_colors[reset]="\033[0m"
    _zcore_colors[bold]="\033[1m"
    _zcore_colors[dim]="\033[2m"
    _zcore_colors[blink]="\033[5m"

    _zcore_colors[black]="\033[30m"
    _zcore_colors[red]="\033[31m"
    _zcore_colors[green]="\033[32m"
    _zcore_colors[yellow]="\033[33m"
    _zcore_colors[blue]="\033[34m"
    _zcore_colors[magenta]="\033[35m"
    _zcore_colors[cyan]="\033[36m"
    _zcore_colors[white]="\033[37m"
  fi

  return 0
}

z::ui::color() {
  emulate -L zsh

  local color_name="$1"
  shift
  local text="$*"

  local color_code="${_zcore_colors[$color_name]}"
  local reset_code="${_zcore_colors[reset]}"

  if [[ -n "$color_code" ]]; then
    print -r -- "${color_code}${text}${reset_code}"
  else
    print -r -- "$text"
  fi

  return 0
}

alias __zuic='z::ui::color'

__z::json::escape() {
  emulate -L zsh
  setopt localoptions extended_glob

  local input="$1"
  local output="$input"

  output="${output//\\/\\\\}"    # Backslash
  output="${output//\"/\\\"}"    # Double quote
  output="${output//$'\n'/\\n}"  # Newline
  output="${output//$'\r'/\\r}"  # Carriage return
  output="${output//$'\t'/\\t}"  # Tab
  output="${output//$'\b'/\\b}"  # Backspace
  output="${output//$'\f'/\\f}"  # Form feed

  print -r -- "$output"
}

typeset -g _cached_hostname=""

__z::sys::hostname() {
  emulate -L zsh

  if [[ -z "$_cached_hostname" ]]; then
    _cached_hostname="${HOST:-${HOSTNAME:-unknown}}"
  fi

  print -r -- "$_cached_hostname"
}

__z::sys::pid() {
  print -r -- "$$"
}

typeset -g _cached_username=""

__z::sys::username() {
  emulate -L zsh

  if [[ -z "$_cached_username" ]]; then
    _cached_username="${USER:-${USERNAME:-unknown}}"
  fi

  print -r -- "$_cached_username"
}

__z::log::update_ts() {
  emulate -L zsh
  setopt no_unset

  if (( ! _zcore_logging[timestamp_cache_enabled] )); then
    _cached_timestamp="${(%):-"%D{%Y-%m-%d %H:%M:%S}"}"
    _cached_iso_timestamp="${(%):-"%D{%Y-%m-%dT%H:%M:%S%z}"}"
    return 0
  fi

  local current_epoch="${EPOCHSECONDS}"
  if (( current_epoch == _timestamp_epoch )); then
    return 0
  fi

  _timestamp_epoch=$(( current_epoch ))
  _cached_timestamp="${(%):-"%D{%Y-%m-%d %H:%M:%S}"}"
  _cached_iso_timestamp="${(%):-"%D{%Y-%m-%dT%H:%M:%S%z}"}"

  return 0
}

z::log::disable_timestamp_cache() {
  _zcore_logging[timestamp_cache_enabled]=0
}

z::log::enable_timestamp_cache() {
  _zcore_logging[timestamp_cache_enabled]=1
}

__z::log::level_name() {
  emulate -L zsh
  local level="$1"
  print -r -- "${_zcore_level_names[$level]:-UNKNOWN}"
}

__z::log::level_number() {
  emulate -L zsh
  local name="${1:u}"  # Convert to uppercase

  case "$name" in
    ERROR) print -r -- "${_zcore_logging[error]}" ;;
    WARN)  print -r -- "${_zcore_logging[warn]}" ;;
    INFO)  print -r -- "${_zcore_logging[info]}" ;;
    DEBUG) print -r -- "${_zcore_logging[debug]}" ;;
    *) return 1 ;;
  esac

  return 0
}

__z::log::rotate_if_needed() {
  emulate -L zsh
  setopt localoptions no_unset
  local logfile="${_zcore_logging[file]}"
  local max_size="${_zcore_logging[rotate_size]}"
  local keep_count="${_zcore_logging[rotate_keep]}"

  [[ ! -f "$logfile" ]] && return 0
  (( max_size <= 0 )) && return 0

  local file_size

  if command -v stat &>/dev/null; then
    # Linux (GNU stat)
    if stat -c%s "$logfile" &>/dev/null 2>&1; then
      file_size=$(stat -c%s "$logfile")
    elif stat -f%z "$logfile" &>/dev/null 2>&1; then
      file_size=$(stat -f%z "$logfile")
    else
      return 1
    fi
  else
    return 1
  fi

  (( file_size < max_size )) && return 0

  local i
  [[ -f "${logfile}.${keep_count}" ]] && rm -f "${logfile}.${keep_count}"

  for (( i = keep_count - 1; i >= 1; i-- )); do
    if [[ -f "${logfile}.${i}" ]]; then
      mv -f "${logfile}.${i}" "${logfile}.$(( i + 1 ))"
    fi
  done

  mv -f "$logfile" "${logfile}.1"
  : > "$logfile"

  return 0
}

__z::log::write_file() {
  emulate -L zsh
  setopt localoptions no_unset

  local message="$1"
  local logfile="${_zcore_logging[file]}"

  [[ -z "$logfile" ]] && return 0

  __z::log::rotate_if_needed

  local logdir="${logfile:h}"
  if [[ ! -d "$logdir" ]]; then
    command mkdir -p "$logdir" 2>/dev/null || return 1
  fi

  if command -v timeout &>/dev/null; then
    print -r -- "$message" | timeout 1s tee -a "$logfile" &>/dev/null
  else
    print -r -- "$message" >> "$logfile" 2>/dev/null
  fi

  return 0
}


z::log::enable_buffering() {
  emulate -L zsh
  _zcore_logging[buffered]=1
  _zcore_buffer_max=${1:-50}
  trap 'z::log::flush' EXIT INT TERM HUP QUIT

  return 0
}

z::log::disable_buffering() {
  emulate -L zsh
  z::log::flush  # Flush any pending messages
  _zcore_logging[buffered]=0
  return 0
}

__z::log::buffer_add() {
  emulate -L zsh
  local message="$1"
  local level="$2"

  _zcore_log_buffer+=("$message")
  (( _zcore_buffer_count++ ))
  if (( level == _zcore_logging[error] || _zcore_buffer_count >= _zcore_buffer_max )); then
    z::log::flush
  fi

  return 0
}

z::log::flush() {
  emulate -L zsh
  setopt localoptions no_unset
  (( ${#_zcore_log_buffer} == 0 )) && return 0

  local logfile="${_zcore_logging[file]}"
  if [[ -z "$logfile" ]]; then
    _zcore_log_buffer=()
    _zcore_buffer_count=0
    return 0
  fi

  __z::log::rotate_if_needed
  local logdir="${logfile:h}"
  if [[ ! -d "$logdir" ]]; then
    command mkdir -p "$logdir" 2>/dev/null || {
      _zcore_log_buffer=()
      _zcore_buffer_count=0
      return 1
    }
  fi

  if command -v timeout &>/dev/null; then
    printf '%s\n' "${_zcore_log_buffer[@]}" | timeout 2s tee -a "$logfile" &>/dev/null
  else
    printf '%s\n' "${_zcore_log_buffer[@]}" >> "$logfile" 2>/dev/null
  fi

  # Clear buffer
  _zcore_log_buffer=()
  _zcore_buffer_count=0

  return 0
}

__z::log::format_json() {
  emulate -L zsh
  setopt localoptions no_unset extended_glob

  local level="$1"
  local message="$2"
  shift 2

  __z::log::update_ts
  local level_name=$(__z::log::level_name "$level")
  local hostname=$(__z::sys::hostname)
  local pid=$(__z::sys::pid)
  local username=$(__z::sys::username)
  local escaped_message=$(__z::json::escape "$message")
  local escaped_hostname=$(__z::json::escape "$hostname")
  local escaped_username=$(__z::json::escape "$username")
  local escaped_level=$(__z::json::escape "$level_name")
  local -a json_parts=(
    "\"timestamp\":\"${_cached_iso_timestamp}\""
    "\"level\":\"${escaped_level}\""
    "\"message\":\"${escaped_message}\""
    "\"hostname\":\"${escaped_hostname}\""
    "\"pid\":${pid}"
    "\"user\":\"${escaped_username}\""
  )

  # Add context fields if provided (key-value pairs)
  while (( $# >= 2 )); do
    local key="$1"
    local value="$2"
    shift 2

    local escaped_key=$(__z::json::escape "$key")
    local escaped_value=$(__z::json::escape "$value")

    json_parts+=("\"${escaped_key}\":\"${escaped_value}\"")
  done

  # Combine into JSON object
  local IFS=","
  print -r -- "{${json_parts[*]}}"

  return 0
}


__z::log::format_text() {
  emulate -L zsh
  setopt localoptions no_unset

  local level="$1"
  local message="$2"
  shift 2

  __z::log::update_ts
  local level_name=$(__z::log::level_name "$level")
  local pid=$(__z::sys::pid)

  local level_color=""
  local level_display=""

  case "$level" in
    ${_zcore_logging[error]})
      level_color="red"
      level_display="${_zcore_colors[bold]}${_zcore_colors[red]}ERROR${_zcore_colors[reset]}"
      ;;
    ${_zcore_logging[warn]})
      level_color="yellow"
      level_display="${_zcore_colors[bold]}${_zcore_colors[yellow]}WARN${_zcore_colors[reset]} "
      ;;
    ${_zcore_logging[info]})
      level_color="green"
      level_display="${_zcore_colors[bold]}${_zcore_colors[green]}INFO${_zcore_colors[reset]} "
      ;;
    ${_zcore_logging[debug]})
      level_color="cyan"
      level_display="${_zcore_colors[bold]}${_zcore_colors[cyan]}DEBUG${_zcore_colors[reset]}"
      ;;
    *)
      level_display="$level_name"
      ;;
  esac

  # Build output in array for efficiency
  local -a output_parts=(
    "${_zcore_colors[dim]}${_cached_timestamp}${_zcore_colors[reset]}"
    "[${level_display}]"
    "${_zcore_colors[dim]}(${pid})${_zcore_colors[reset]}"
    "${message}"
  )

  if (( $# >= 2 )); then
    local -a context_parts=()

    while (( $# >= 2 )); do
      local key="$1"
      local value="$2"
      shift 2

      context_parts+=("${_zcore_colors[dim]}${key}${_zcore_colors[reset]}=${_zcore_colors[cyan]}${value}${_zcore_colors[reset]}")
    done

    if (( ${#context_parts} > 0 )); then
      local context_str="${(j: :)context_parts}"
      output_parts+=("${_zcore_colors[dim]}|${_zcore_colors[reset]}" "$context_str")
    fi
  fi

  print -r -- "${(j: :)output_parts}"

  return 0
}

__z::log::format() {
  emulate -L zsh

  local level="$1"
  local message="$2"
  shift 2

  case "${_zcore_logging[format]}" in
    json)
      __z::log::format_json "$level" "$message" "$@"
      ;;
    text|*)
      __z::log::format_text "$level" "$message" "$@"
      ;;
  esac

  return 0
}

__z::log::engine() {
  emulate -L zsh
  setopt localoptions no_unset

  # Recursion protection
  if (( _zcore_logging[depth] >= _zcore_logging[max_depth] )); then
    print -u2 "ZCORE_LOG: Maximum recursion depth reached"
    return 1
  fi

  (( _zcore_logging[depth]++ ))

  local level="$1"
  local message="$2"
  shift 2

  local console_level="${_zcore_logging[level]}"
  local file_level="${_zcore_logging[file_level]}"

  (( file_level == -1 )) && file_level="$console_level"

  local should_console=0
  local should_file=0

  (( level <= console_level )) && should_console=1
  [[ -n "${_zcore_logging[file]}" ]] && (( level <= file_level )) && should_file=1

  if (( !should_console && !should_file )); then
    (( _zcore_logging[depth]-- ))
    return 0
  fi

  local formatted
  formatted=$(__z::log::format "$level" "$message" "$@")
  if (( should_console )); then
    if (( level == _zcore_logging[error] )); then
      print -u2 -r -- "$formatted"
    else
      print -r -- "$formatted"
    fi
  fi

  # Output to file if appropriate
  if (( should_file )); then
    if (( _zcore_logging[buffered] )); then
      __z::log::buffer_add "$formatted" "$level"
    else
      __z::log::write_file "$formatted"
    fi
  fi

  (( _zcore_logging[depth]-- ))
  return 0
}


z::log::error() {
  emulate -L zsh
  local console_level="${_zcore_logging[level]}"
  local file_level="${_zcore_logging[file_level]}"
  (( file_level == -1 )) && file_level="$console_level"
  if (( _zcore_logging[error] > console_level && _zcore_logging[error] > file_level )); then
    return 0
  fi

  __z::log::engine "${_zcore_logging[error]}" "$@"
}
z::log::errorf() {
  emulate -L zsh

  # Lazy evaluation
  local console_level="${_zcore_logging[level]}"
  local file_level="${_zcore_logging[file_level]}"
  (( file_level == -1 )) && file_level="$console_level"

  if (( _zcore_logging[error] > console_level && _zcore_logging[error] > file_level )); then
    return 0
  fi

  local format="$1"
  shift

  local message
  message=$(printf "$format" "$@" 2>/dev/null) || message="<printf format error>"

  __z::log::engine "${_zcore_logging[error]}" "$message"
}

z::log::if_error() {
  emulate -L zsh

  local console_level="${_zcore_logging[level]}"
  local file_level="${_zcore_logging[file_level]}"
  (( file_level == -1 )) && file_level="$console_level"

  # Return 0 (true) if either console or file will log errors
  (( _zcore_logging[error] <= console_level || _zcore_logging[error] <= file_level ))
}

z::log::warn() {
  emulate -L zsh
  local console_level="${_zcore_logging[level]}"
  local file_level="${_zcore_logging[file_level]}"
  (( file_level == -1 )) && file_level="$console_level"

  if (( _zcore_logging[warn] > console_level && _zcore_logging[warn] > file_level )); then
    return 0
  fi

  __z::log::engine "${_zcore_logging[warn]}" "$@"
}

z::log::warnf() {
  emulate -L zsh

  # Lazy evaluation
  local console_level="${_zcore_logging[level]}"
  local file_level="${_zcore_logging[file_level]}"
  (( file_level == -1 )) && file_level="$console_level"

  if (( _zcore_logging[warn] > console_level && _zcore_logging[warn] > file_level )); then
    return 0
  fi

  local format="$1"
  shift

  local message
  message=$(printf "$format" "$@" 2>/dev/null) || message="<printf format error>"

  __z::log::engine "${_zcore_logging[warn]}" "$message"
}

z::log::if_warn() {
  emulate -L zsh

  local console_level="${_zcore_logging[level]}"
  local file_level="${_zcore_logging[file_level]}"
  (( file_level == -1 )) && file_level="$console_level"

  (( _zcore_logging[warn] <= console_level || _zcore_logging[warn] <= file_level ))
}
z::log::info() {
  emulate -L zsh
  local console_level="${_zcore_logging[level]}"
  local file_level="${_zcore_logging[file_level]}"
  (( file_level == -1 )) && file_level="$console_level"

  if (( _zcore_logging[info] > console_level && _zcore_logging[info] > file_level )); then
    return 0
  fi

  __z::log::engine "${_zcore_logging[info]}" "$@"
}

z::log::infof() {
  emulate -L zsh

  # Lazy evaluation
  local console_level="${_zcore_logging[level]}"
  local file_level="${_zcore_logging[file_level]}"
  (( file_level == -1 )) && file_level="$console_level"

  if (( _zcore_logging[info] > console_level && _zcore_logging[info] > file_level )); then
    return 0
  fi

  local format="$1"
  shift

  local message
  message=$(printf "$format" "$@" 2>/dev/null) || message="<printf format error>"

  __z::log::engine "${_zcore_logging[info]}" "$message"
}
z::log::if_info() {
  emulate -L zsh

  local console_level="${_zcore_logging[level]}"
  local file_level="${_zcore_logging[file_level]}"
  (( file_level == -1 )) && file_level="$console_level"

  (( _zcore_logging[info] <= console_level || _zcore_logging[info] <= file_level ))
}
z::log::debug() {
  emulate -L zsh
  local console_level="${_zcore_logging[level]}"
  local file_level="${_zcore_logging[file_level]}"
  (( file_level == -1 )) && file_level="$console_level"

  if (( _zcore_logging[debug] > console_level && _zcore_logging[debug] > file_level )); then
    return 0
  fi

  __z::log::engine "${_zcore_logging[debug]}" "$@"
}

z::log::debugf() {
  emulate -L zsh

  # Lazy evaluation
  local console_level="${_zcore_logging[level]}"
  local file_level="${_zcore_logging[file_level]}"
  (( file_level == -1 )) && file_level="$console_level"

  if (( _zcore_logging[debug] > console_level && _zcore_logging[debug] > file_level )); then
    return 0
  fi

  local format="$1"
  shift

  local message
  message=$(printf "$format" "$@" 2>/dev/null) || message="<printf format error>"

  __z::log::engine "${_zcore_logging[debug]}" "$message"
}
z::log::if_debug() {
  emulate -L zsh

  local console_level="${_zcore_logging[level]}"
  local file_level="${_zcore_logging[file_level]}"
  (( file_level == -1 )) && file_level="$console_level"

  (( _zcore_logging[debug] <= console_level || _zcore_logging[debug] <= file_level ))
}


z::log::with_context() {
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  if (( $# < 2 || $# % 2 != 0 )); then
    z::log::error "with_context requires even number of arguments (key-value pairs), got $#"
    return 1
  fi

  local -a context_pairs=("$@")
  local i
  for (( i=1; i<=${#context_pairs}; i+=2 )); do
    local key="${context_pairs[i]}"
    local value="${context_pairs[i+1]}"

    if [[ -z "$key" ]]; then
      z::log::error "Context key cannot be empty at position $i"
      return 1
    fi

    if [[ "$key" =~ [^a-zA-Z0-9_-] ]]; then
      z::log::error "Context key '$key' contains invalid characters (only alphanumeric, _, - allowed)"
      return 1
    fi
  done

  if (( ${#_zcore_log_contexts} >= _ZCORE_MAX_CONTEXTS )); then
    z::log::warn "Context limit ($_ZCORE_MAX_CONTEXTS) reached, cleaning oldest context"
    _z_log_cleanup_oldest_context
  fi

  local ctx_id
  local max_attempts=10
  local attempt=0

  while (( attempt < max_attempts )); do
    (( _zcore_context_counter++ ))
    ctx_id="zlog_ctx_${_zcore_context_counter}_${RANDOM}_${EPOCHSECONDS}_$$"

    [[ -z "${_zcore_log_contexts[$ctx_id]:-}" ]] && break

    (( attempt++ ))
    sleep 0.001
  done

  if (( attempt >= max_attempts )); then
    z::log::error "Failed to generate unique context ID after $max_attempts attempts"
    return 1
  fi

  _zcore_log_contexts[$ctx_id]="${(pj:\0:)context_pairs}"
  _zcore_log_contexts_parsed[$ctx_id]="${(@)context_pairs}"
  _zcore_log_contexts_order+=("$ctx_id")

  _z_log_create_context_functions "$ctx_id" || {
    z::log::error "Failed to create context functions for $ctx_id"
    unset "_zcore_log_contexts[$ctx_id]"
    unset "_zcore_log_contexts_parsed[$ctx_id]"
    _zcore_log_contexts_order=("${(@)_zcore_log_contexts_order:#$ctx_id}")
    return 1
  }

  print -r -- "$ctx_id"
  return 0
}
_z_log_create_context_functions() {
  emulate -L zsh

  local ctx_id="$1"
  local -a match mbegin mend

  if [[ ! "$ctx_id" =~ ^zlog_ctx_[0-9]+_[0-9]+_[0-9]+_[0-9]+$ ]]; then
    print -u2 "Error: Invalid context ID format: $ctx_id"
    return 1
  fi

  local level
  for level in error warn info debug; do
    _z_log_create_context_function "$ctx_id" "$level" "false" || return 1
    _z_log_create_context_function "$ctx_id" "$level" "true" || return 1
  done

  return 0
}

_z_log_create_context_function() {
  emulate -L zsh

  local ctx_id="$1"
  local level="$2"
  local formatted="$3"
  local -a match mbegin mend
  local func_name="${ctx_id}::${level}"
  [[ "$formatted" == "true" ]] && func_name="${func_name}f"

  if [[ ! "$func_name" =~ ^zlog_ctx_[0-9]+_[0-9]+_[0-9]+_[0-9]+::(error|warn|info|debug)f?$ ]]; then
    print -u2 "Error: Invalid function name would be created: $func_name"
    return 1
  fi

  if [[ "$formatted" == "true" ]]; then
    eval "
      function ${func_name} {
        emulate -L zsh
        setopt localoptions no_unset

        # Extract context ID from function name
        local func_ctx_id=\"\${0%%::*}\"

        # Check if context still exists
        if [[ -z \"\${_zcore_log_contexts[\$func_ctx_id]:-}\" ]]; then
          print -u2 \"Warning: Context \$func_ctx_id no longer exists\"
          return 1
        fi

        # Get format string and arguments
        local fmt=\"\$1\"
        shift

        # Format message using printf
        local msg
        if ! msg=\$(printf \"\$fmt\" \"\$@\" 2>&1); then
          msg=\"<printf error: \$msg>\"
        fi

        # Get context arguments from storage
        local -a ctx_args
        ctx_args=(\"\${(@0)_zcore_log_contexts[\$func_ctx_id]}\")

        # Extract level name from function name (remove 'f' suffix if present)
        local func_level=\"\${0##*::}\"
        func_level=\"\${func_level%f}\"

        # Call the appropriate log function with context
        z::log::\${func_level} \"\$msg\" \"\${ctx_args[@]}\"
      }
    "
  else
    # Unformatted version
    eval "
      function ${func_name} {
        emulate -L zsh
        setopt localoptions no_unset

        # Extract context ID from function name
        local func_ctx_id=\"\${0%%::*}\"

        # Check if context still exists
        if [[ -z \"\${_zcore_log_contexts[\$func_ctx_id]:-}\" ]]; then
          print -u2 \"Warning: Context \$func_ctx_id no longer exists\"
          return 1
        fi

        # Get message and additional key-value pairs
        local msg=\"\$1\"
        shift

        # Get context arguments from storage
        local -a ctx_args
        ctx_args=(\"\${(@0)_zcore_log_contexts[\$func_ctx_id]}\")

        # Extract level name from function name
        local func_level=\"\${0##*::}\"

        # Call the appropriate log function with context and additional args
        z::log::\${func_level} \"\$msg\" \"\${ctx_args[@]}\" \"\$@\"
      }
    "
  fi

  return 0
}

_z_log_cleanup_oldest_context() {
  emulate -L zsh
  setopt localoptions no_unset

  (( ${#_zcore_log_contexts_order} > 0 )) || return 0

  local oldest_ctx="${_zcore_log_contexts_order[1]}"
  z::log::remove_context "$oldest_ctx"
}



z::log::remove_context() {
  emulate -L zsh
  setopt localoptions no_unset

  local ctx_id="$1"

  if [[ -z "$ctx_id" ]]; then
    z::log::error "remove_context requires a context ID"
    return 1
  fi

  [[ -n "${_zcore_log_contexts[$ctx_id]:-}" ]] || {
    z::log::debug "Context $ctx_id does not exist or already removed"
    return 1
  }

  unset "_zcore_log_contexts[$ctx_id]"
  unset "_zcore_log_contexts_parsed[$ctx_id]"

  _zcore_log_contexts_order=("${(@)_zcore_log_contexts_order:#$ctx_id}")

  local level suffix
  for level in error warn info debug; do
    for suffix in "" "f"; do
      local func_name="${ctx_id}::${level}${suffix}"
      if (( ${+functions[$func_name]} )); then
        unfunction "$func_name" 2>/dev/null
      fi
    done
  done

  return 0
}


z::log::remove_all_contexts() {
  emulate -L zsh
  setopt localoptions no_unset

  local ctx_id
  for ctx_id in "${_zcore_log_contexts_order[@]}"; do
    z::log::remove_context "$ctx_id"
  done

  _zcore_log_contexts=()
  _zcore_log_contexts_parsed=()
  _zcore_log_contexts_order=()

  return 0
}

z::log::list_contexts() {
  emulate -L zsh
  setopt localoptions no_unset

  local ctx_id
  for ctx_id in "${_zcore_log_contexts_order[@]}"; do
    if [[ -n "${_zcore_log_contexts[$ctx_id]:-}" ]]; then
      local -a ctx_data
      ctx_data=("${(@0)_zcore_log_contexts[$ctx_id]}")

      print -n "$ctx_id "

      local i
      for (( i=1; i<=${#ctx_data}; i+=2 )); do
        print -n "${ctx_data[i]}=${ctx_data[i+1]} "
      done

      print
    fi
  done
}


z::log::benchmark() {
  emulate -L zsh
  setopt localoptions no_unset

  # Validate input
  if (( $# < 2 )); then
    z::log::error "benchmark requires operation name and command"
    return 1
  fi

  local operation_name="$1"
  shift

  # Validate operation name
  if [[ -z "$operation_name" ]]; then
    z::log::error "benchmark operation name cannot be empty"
    return 1
  fi

  # Only benchmark if info level is active (performance optimization)
  if ! z::log::if_info; then
    # Just execute without timing
    "$@"
    return $?
  fi

  local start_time=$EPOCHREALTIME

  # Execute command and capture output/errors if needed
  local exit_code
  "$@"
  exit_code=$?

  local end_time=$EPOCHREALTIME

  # Calculate duration in milliseconds
  local duration_ms
  duration_ms=$(( (end_time - start_time) * 1000 ))

  # Format duration
  local duration_str
  duration_str=$(_z_log_format_duration "$duration_ms")

  # Log the benchmark result
  z::log::info "Benchmark: ${operation_name}" \
    "duration" "$duration_str" \
    "exit_code" "$exit_code"

  return $exit_code
}


z::log::benchmark_start() {
  emulate -L zsh
  setopt localoptions no_unset

  local operation_name="$1"

  # Validate input
  if [[ -z "$operation_name" ]]; then
    z::log::error "benchmark_start requires operation name"
    return 1
  fi

  # Only benchmark if info level is active
  if ! z::log::if_info; then
    # Return empty to signal no timing
    print -r -- ""
    return 0
  fi

  # Check timer limit and cleanup if necessary
  if (( ${#_zcore_benchmark_timers} >= _ZCORE_MAX_TIMERS )); then
    z::log::warn "Timer limit ($_ZCORE_MAX_TIMERS) reached, cleaning oldest timer"
    _z_log_cleanup_oldest_timer
  fi

  # Generate unique timer ID with collision protection
  local timer_id
  local max_attempts=10
  local attempt=0

  while (( attempt < max_attempts )); do
    timer_id="zbt_${RANDOM}_${EPOCHSECONDS}_$$"

    # Check for collision
    [[ -z "${_zcore_benchmark_timers[$timer_id]:-}" ]] && break

    (( attempt++ ))
    sleep 0.001
  done

  if (( attempt >= max_attempts )); then
    z::log::error "Failed to generate unique timer ID after $max_attempts attempts"
    return 1
  fi

  # Store timer data: start_time|operation_name
  _zcore_benchmark_timers[$timer_id]="${EPOCHREALTIME}|${operation_name}"
  _zcore_benchmark_timer_order+=("$timer_id")

  # Return timer ID
  print -r -- "$timer_id"
  return 0
}

z::log::benchmark_end() {
  emulate -L zsh
  setopt localoptions no_unset

  local timer_id="$1"

  # Handle empty timer (when info logging is disabled)
  if [[ -z "$timer_id" ]]; then
    return 0
  fi

  # Validate input
  if [[ ! "$timer_id" =~ ^zbt_[0-9]+_[0-9]+_[0-9]+$ ]]; then
    z::log::error "Invalid timer ID format: $timer_id"
    return 1
  fi

  # Check if timer exists
  if [[ -z "${_zcore_benchmark_timers[$timer_id]:-}" ]]; then
    z::log::error "Timer not found: $timer_id"
    return 1
  fi

  # Parse timer data
  local timer_data="${_zcore_benchmark_timers[$timer_id]}"
  local start_time="${timer_data%%|*}"
  local operation_name="${timer_data#*|}"

  # Calculate duration
  local end_time=$EPOCHREALTIME
  local duration_ms
  duration_ms=$(( (end_time - start_time) * 1000 ))

  # Format duration
  local duration_str
  duration_str=$(_z_log_format_duration "$duration_ms")

  # Log the benchmark result
  z::log::info "Benchmark completed: ${operation_name}" \
    "duration" "$duration_str"

  # Cleanup timer
  unset "_zcore_benchmark_timers[$timer_id]"
  _zcore_benchmark_timer_order=("${(@)_zcore_benchmark_timer_order:#$timer_id}")

  return 0
}

_z_log_cleanup_oldest_timer() {
  emulate -L zsh
  setopt localoptions no_unset

  [[ ${#_zcore_benchmark_timer_order} -gt 0 ]] || return 0

  local oldest_timer="${_zcore_benchmark_timer_order[1]}"

  # Remove from storage
  unset "_zcore_benchmark_timers[$oldest_timer]"
  _zcore_benchmark_timer_order=("${(@)_zcore_benchmark_timer_order[@]:1}")

  z::log::debug "Cleaned up oldest timer: $oldest_timer"
}

_z_log_format_duration() {
  local duration_ms="$1"

  if (( duration_ms < 1 )); then
    printf "%.3fms" "$duration_ms"
  elif (( duration_ms < 1000 )); then
    printf "%.2fms" "$duration_ms"
  elif (( duration_ms < 60000 )); then
    printf "%.2fs" "$(( duration_ms / 1000.0 ))"
  else
    local minutes=$(( duration_ms / 60000 ))
    local seconds=$(( (duration_ms % 60000) / 1000.0 ))
    printf "%dm%.2fs" "$minutes" "$seconds"
  fi
}
