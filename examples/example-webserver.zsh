#!/usr/bin/env zsh
# ==============================================================================
#  zlog — Example: Web Server Request Logger
#  Demonstrates context loggers, structured fields, rate limiting, buffering,
#  and file rotation in a realistic web-server simulation.
#  Run: zsh examples/example-webserver.zsh
# ==============================================================================

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/../zlog"

typeset -g APP_NAME="WebServer"
typeset -g APP_VERSION="1.0.0"
typeset -g LOG_DIR="/tmp/zlog_webserver_$$"
typeset -g APP_LOG="$LOG_DIR/app.log"
typeset -g ACCESS_LOG="$LOG_DIR/access.log"
typeset -g ERROR_LOG="$LOG_DIR/error.log"

###############################################################################
# Setup
###############################################################################

setup_logging() {
  mkdir -p "$LOG_DIR"

  z::log::setup "$APP_LOG" info text
  z::log::set_rotation 1 "10MB" 5
  z::log::enable_buffering 100
  z::log::register_cleanup

  z::log::info "Application starting" \
    name    "$APP_NAME" \
    version "$APP_VERSION" \
    log_dir "$LOG_DIR"
}

###############################################################################
# Request handling
###############################################################################

generate_request_id() {
  REPLY="req_${RANDOM}${RANDOM}_${EPOCHSECONDS}"
}

log_access() {
  local req_method="$1" req_path="$2" http_status="$3" duration_ms="$4" client_ip="$5"
  local ts; ts=$(z::log::get_timestamp human)
  print "$ts $client_ip \"$req_method $req_path\" $http_status ${duration_ms}ms" >> "$ACCESS_LOG"
}

simulate_db_query() {
  local ctx="$1" table="$2"
  ${ctx}::debug "Executing query" table "$table"
  sleep 0.0$((RANDOM % 5 + 1))
  local rows=$(( RANDOM % 100 + 1 ))
  ${ctx}::debug "Query complete" table "$table" rows "$rows"
}

handle_request() {
  local req_method="$1" req_path="$2" client_ip="$3"

  generate_request_id
  local request_id="$REPLY"

  z::log::with_context \
    request_id "$request_id" \
    method     "$req_method" \
    path       "$req_path" \
    client_ip  "$client_ip"
  local ctx="$REPLY"

  ${ctx}::info "Request received"

  local start=$EPOCHREALTIME
  local http_status=200

  case "$req_path" in
    /api/users)
      simulate_db_query "$ctx" users
      ;;
    /api/products)
      simulate_db_query "$ctx" products
      ;;
    /api/slow)
      ${ctx}::warn "Slow endpoint accessed"
      sleep 0.3
      ;;
    /api/error)
      ${ctx}::error "Simulated server error"
      http_status=500
      ;;
    *)
      ${ctx}::warn "Unknown endpoint"
      http_status=404
      ;;
  esac

  local duration_ms=$(( (EPOCHREALTIME - start) * 1000 ))

  if (( duration_ms > 100 )); then
    z::log::rate_limit "slow-req" 5 60 warn "Slow request" \
      path "$req_path" duration_ms "$duration_ms"
  fi

  ${ctx}::info "Request completed" http_status "$http_status" duration_ms "$duration_ms"

  log_access "$req_method" "$req_path" "$http_status" "$duration_ms" "$client_ip"

  z::log::remove_context "$ctx"
}

###############################################################################
# System stats
###############################################################################

log_system_stats() {
  local mem_kb; mem_kb=$(ps -o rss= -p $$ 2>/dev/null || print 0)
  local app_log_bytes=0
  [[ -f "$APP_LOG" ]] && app_log_bytes=$(wc -c < "$APP_LOG")

  local app_log_size
  if (( app_log_bytes >= 1048576 )); then
    app_log_size="$(printf '%.1fMB' $(( app_log_bytes / 1048576.0 )))"
  elif (( app_log_bytes >= 1024 )); then
    app_log_size="$(printf '%.1fKB' $(( app_log_bytes / 1024.0 )))"
  else
    app_log_size="${app_log_bytes}B"
  fi

  z::log::info "System stats" \
    memory_kb    "$mem_kb" \
    app_log_size "$app_log_size" \
    buffer_count "$(z::log::get_buffer_count)"
}

###############################################################################
# Main simulation
###############################################################################

run_webserver_simulation() {
  setup_logging

  print "╔════════════════════════════════════════════════════════════════╗"
  print "║           zlog — Web Server Logger Example                    ║"
  print "╠════════════════════════════════════════════════════════════════╣"
  printf "║  App log:    %-47s║\n" "$APP_LOG"
  printf "║  Access log: %-47s║\n" "$ACCESS_LOG"
  printf "║  Error log:  %-47s║\n" "$ERROR_LOG"
  print "╚════════════════════════════════════════════════════════════════╝"
  print

  local -a req_methods=(GET POST PUT DELETE)
  local -a req_paths=(/api/users /api/products /api/slow /api/error /api/unknown)
  local -a client_ips=(192.168.1.100 192.168.1.101 203.0.113.42 198.51.100.50)

  print "Simulating 30 HTTP requests..."
  local i
  for i in {1..30}; do
    local req_method="${req_methods[$((RANDOM % ${#req_methods} + 1))]}"
    local req_path="${req_paths[$((RANDOM % ${#req_paths} + 1))]}"
    local client_ip="${client_ips[$((RANDOM % ${#client_ips} + 1))]}"

    handle_request "$req_method" "$req_path" "$client_ip"

    if (( i % 10 == 0 )); then
      log_system_stats
      print -n "."
    fi

    sleep 0.01
  done

  print "\n\nSimulation complete."

  z::log::flush

  z::log::colorize bold 'Application Log (last 10 lines):'
  print "\n$REPLY"
  z::log::colorize dim '────────────────────────────────────────────────────────────────'
  print "$REPLY"
  tail -10 "$APP_LOG" 2>/dev/null
  z::log::colorize dim '────────────────────────────────────────────────────────────────'
  print "$REPLY"

  z::log::colorize bold 'Access Log (last 10 lines):'
  print "\n$REPLY"
  z::log::colorize dim '────────────────────────────────────────────────────────────────'
  print "$REPLY"
  tail -10 "$ACCESS_LOG" 2>/dev/null
  z::log::colorize dim '────────────────────────────────────────────────────────────────'
  print "$REPLY"

  z::log::cleanup

  z::log::colorize green '✓ Example complete.'
  print "\n$REPLY  Logs saved to: $LOG_DIR"
}

if [[ "${ZSH_EVAL_CONTEXT}" == "toplevel" ]]; then
  run_webserver_simulation
fi
