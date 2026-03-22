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

# ── Nexus environment config ───────────────────────────────────────────────────
# Persistent key=value store at ~/.config/faigrid/grid.env
# Sourced automatically from ~/.bashrc after first configure run.

_NEXUS_ENV_FILE="${HOME}/.config/faigrid/grid.env"

# Write or update a single export in grid.env
grid_write_env() {
  local key="$1" val="$2"
  mkdir -p "$(dirname "$_NEXUS_ENV_FILE")"
  if [[ ! -f "$_NEXUS_ENV_FILE" ]]; then
    printf '# fusionAIze Grid — Tool Environment\n# source ~/.config/faigrid/grid.env\n' \
      > "$_NEXUS_ENV_FILE"
    chmod 600 "$_NEXUS_ENV_FILE"
  fi
  local tmp
  tmp=$(mktemp)
  grep -v "^export ${key}=" "$_NEXUS_ENV_FILE" > "$tmp" && mv "$tmp" "$_NEXUS_ENV_FILE"
  printf 'export %s="%s"\n' "$key" "$val" >> "$_NEXUS_ENV_FILE"
  chmod 600 "$_NEXUS_ENV_FILE"
}

# Read a single key from grid.env; empty string if not set
grid_read_env() {
  local key="$1"
  grep "^export ${key}=" "$_NEXUS_ENV_FILE" 2>/dev/null | cut -d'"' -f2 || echo ""
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
      printf '[ -f "%s" ] && source "%s"\n' "$_NEXUS_ENV_FILE" "$_NEXUS_ENV_FILE"
    } >> "$rc_file"
    info "Added grid.env source hook to ${rc_file}"
  fi
}

# UI Helpers
print_header() {
  printf "\n%b%b=== %s ===%b\n\n" "${C_BOLD}" "${C_MAGENTA}" "$1" "${C_RESET}"
}

# Centralized Logging Aggregator
log_event() {
  local COMPONENT=$1
  local SEVERITY=$2
  local MESSAGE=$3
  local LOG_DIR="/var/log/nexus"
  local LOG_FILE="${LOG_DIR}/nexus-system.log"
  
  if [[ ! -d "$LOG_DIR" ]]; then
    sudo mkdir -p "$LOG_DIR" 2>/dev/null || true
    sudo chmod 777 "$LOG_DIR" 2>/dev/null || true
  fi
  
  if [[ -w "$LOG_DIR" ]] || [[ -f "$LOG_FILE" && -w "$LOG_FILE" ]]; then
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") | ${COMPONENT} | [${SEVERITY}] | ${MESSAGE}" >> "$LOG_FILE"
  fi
}

# Simple Log Rotation
rotate_logs() {
  local LOG_FILE="/var/log/nexus/nexus-system.log"
  local MAX_SIZE_KB=5120 # 5MB limit
  
  if [[ -f "$LOG_FILE" ]]; then
    local SIZE_KB
    SIZE_KB=$(du -k "$LOG_FILE" | cut -f1)
    if [[ "$SIZE_KB" -gt "$MAX_SIZE_KB" ]]; then
      log_event "system" "INFO" "Rotating logs (Size: ${SIZE_KB}KB)"
      mv "$LOG_FILE" "${LOG_FILE}.old"
      touch "$LOG_FILE"
      chmod 666 "$LOG_FILE" 2>/dev/null || true
    fi
  fi
}
