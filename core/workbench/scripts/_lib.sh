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

# Logging
info() { echo -e "${C_CYAN}[INFO]${C_RESET} $*"; }
success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
error() { echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2; }
die() { error "$@"; exit 1; }

# UI Helpers
print_header() {
  echo -e "\n${C_BOLD}${C_MAGENTA}=== $1 ===${C_RESET}\n"
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
