#!/usr/bin/env bash
# Shared library for Workbench Scripts

# Colors
export C_RESET='\033[0m'
export C_RED='\033[0;31m'
export C_GREEN='\033[0;32m'
export C_YELLOW='\033[0;33m'
export C_BLUE='\033[0;34m'
export C_MAGENTA='\033[0;35m'
export C_CYAN='\033[0;36m'
export C_BOLD='\033[1m'
export C_DIM='\033[2m'

# Logging
info() { printf "%b[INFO]%b %s\n" "${C_CYAN}" "${C_RESET}" "$*"; }
success() { printf "%b[SUCCESS]%b %s\n" "${C_GREEN}" "${C_RESET}" "$*"; }
warn() { printf "%b[WARN]%b %s\n" "${C_YELLOW}" "${C_RESET}" "$*"; }
error() { printf "%b[ERROR]%b %s\n" "${C_RED}" "${C_RESET}" "$*" >&2; }
die() { error "$@"; exit 1; }

# OS / package manager detection
# Prints: apt | dnf | yum | brew | unknown
detect_pkg_manager() {
  if   command -v apt-get >/dev/null 2>&1; then echo "apt"
  elif command -v dnf     >/dev/null 2>&1; then echo "dnf"
  elif command -v yum     >/dev/null 2>&1; then echo "yum"
  elif command -v brew    >/dev/null 2>&1; then echo "brew"
  else                                          echo "unknown"
  fi
}

# ── Grid environment config ───────────────────────────────────────────────────
# Persistent key=value store at ~/.config/faigrid/grid.env
# Sourced automatically from ~/.bashrc after first configure run.

_GRID_ENV_FILE="${HOME}/.config/faigrid/grid.env"

# Write or update a single export in grid.env
grid_write_env() {
  local key="$1" val="$2"
  mkdir -p "$(dirname "$_GRID_ENV_FILE")"
  if [[ ! -f "$_GRID_ENV_FILE" ]]; then
    printf '# fusionAIze Grid — Tool Environment\n# source ~/.config/faigrid/grid.env\n' \
      > "$_GRID_ENV_FILE"
    chmod 600 "$_GRID_ENV_FILE"
  fi
  local tmp
  tmp=$(mktemp)
  grep -v "^export ${key}=" "$_GRID_ENV_FILE" > "$tmp" && mv "$tmp" "$_GRID_ENV_FILE"
  printf 'export %s="%s"\n' "$key" "$val" >> "$_GRID_ENV_FILE"
  chmod 600 "$_GRID_ENV_FILE"
}

# Read a single key from grid.env; empty string if not set
grid_read_env() {
  local key="$1"
  grep "^export ${key}=" "$_GRID_ENV_FILE" 2>/dev/null | cut -d'"' -f2 || echo ""
}

# Mask a secret for safe display: first 4 chars + ****
grid_mask() {
  local val="$1"
  if [[ -z "$val" ]]; then echo "(not set)"; return; fi
  if [[ ${#val} -le 8 ]]; then echo "****"; return; fi
  printf '%s****\n' "${val:0:4}"
}

# Add source hook to ~/.bashrc if not already present
grid_ensure_sourced() {
  local rc_file="${HOME}/.bashrc"
  if ! grep -q "faigrid/grid.env" "$rc_file" 2>/dev/null; then
    {
      printf '\n# fusionAIze Grid — tool environment\n'
      printf '[ -f "%s" ] && source "%s"\n' "$_GRID_ENV_FILE" "$_GRID_ENV_FILE"
    } >> "$rc_file"
    info "Added grid.env source hook to ${rc_file}"
  fi
}

# UI Helpers
print_header() {
  printf "\n%b%b=== %s ===%b\n\n" "${C_BOLD}" "${C_MAGENTA}" "$1" "${C_RESET}"
}

# JSON-escape a value for safe embedding in a JSONL line
_json_escape() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | tr -d '\000-\037'
}

# Centralized Logging Aggregator
log_event() {
  local COMPONENT=$1
  local SEVERITY=$2
  local MESSAGE=$3
  local LOG_DIR="${LOG_DIR:-/var/log/faigrid}"
  local LOG_FILE="${LOG_DIR}/grid-system.log"
  local EVENTS_FILE="${LOG_DIR}/grid-events.jsonl"

  if [[ ! -d "$LOG_DIR" ]]; then
    sudo mkdir -p "$LOG_DIR" 2>/dev/null || true
    sudo chown root:adm "$LOG_DIR" 2>/dev/null || true
    sudo chmod 750 "$LOG_DIR" 2>/dev/null || true
  fi

  if [[ ! -w "$EVENTS_FILE" ]]; then
    if [[ -w "$LOG_DIR" ]]; then
      touch "$EVENTS_FILE" 2>/dev/null || true
    else
      sudo touch "$EVENTS_FILE" 2>/dev/null || true
      sudo chown root:adm "$EVENTS_FILE" 2>/dev/null || true
      sudo chmod 640 "$EVENTS_FILE" 2>/dev/null || true
    fi
  fi

  if [[ -w "$LOG_DIR" ]] || [[ -f "$LOG_FILE" && -w "$LOG_FILE" ]]; then
    local json
    json=$(printf '{"ts":"%s","component":"%s","severity":"%s","message":"%s"}' \
      "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      "$(_json_escape "$COMPONENT")" \
      "$(_json_escape "$SEVERITY")" \
      "$(_json_escape "$MESSAGE")")
    printf '%s\n' "$json" >> "$LOG_FILE"
    if [[ -f "$EVENTS_FILE" ]] && [[ -w "$EVENTS_FILE" ]]; then
      printf '%s\n' "$json" >> "$EVENTS_FILE"
    fi
  fi
}

# Simple Log Rotation
rotate_logs() {
  local LOG_FILE="/var/log/faigrid/grid-system.log"
  local MAX_SIZE_KB=5120 # 5MB limit
  
  if [[ -f "$LOG_FILE" ]]; then
    local SIZE_KB
    SIZE_KB=$(du -k "$LOG_FILE" | cut -f1)
    if [[ "$SIZE_KB" -gt "$MAX_SIZE_KB" ]]; then
      log_event "system" "INFO" "Rotating logs (Size: ${SIZE_KB}KB)"
      mv "$LOG_FILE" "${LOG_FILE}.old"
      touch "$LOG_FILE"
      chmod 640 "$LOG_FILE" 2>/dev/null || true
      sudo chown root:adm "$LOG_FILE" 2>/dev/null || true
    fi
  fi
}
