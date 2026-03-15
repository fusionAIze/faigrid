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
