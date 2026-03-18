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
