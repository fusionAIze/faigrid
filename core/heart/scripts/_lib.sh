#!/usr/bin/env bash
# Shared utilities for grid-core heart scripts.
# Source this file; do NOT execute it directly.

# ── Output helpers ─────────────────────────────────────────────────────────────
_H_GREEN='\033[0;32m'; _H_YELLOW='\033[1;33m'
_H_RED='\033[0;31m';   _H_CYAN='\033[0;36m'; _H_NC='\033[0m'

success() { echo -e "${_H_GREEN}✔${_H_NC}  $*"; }
info()    { echo -e "${_H_CYAN}ℹ${_H_NC}  $*"; }
warn()    { echo -e "${_H_YELLOW}⚠${_H_NC}  $*"; }
error()   { echo -e "${_H_RED}✖${_H_NC}  $*" >&2; }

# ── Compose path discovery ─────────────────────────────────────────────────────
# Sets STACK_DIR, COMPOSE_DIR, ENV_FILE in caller's scope.
# Requires CORE_ROOT to be set before calling.
resolve_compose_paths() {
    STACK_DIR="/opt/faigrid/core-heart"
    if [[ ! -d "${STACK_DIR}" ]]; then
        STACK_DIR="${CORE_ROOT}/heart"
    fi

    COMPOSE_DIR="${STACK_DIR}/compose"
    ENV_FILE="${STACK_DIR}/.env"

    # Fallback 1: compose file may live directly in STACK_DIR (no /compose subdir)
    if [[ ! -d "${COMPOSE_DIR}" ]]; then
        if [[ -f "${STACK_DIR}/docker-compose.yml" ]] || [[ -f "${STACK_DIR}/compose.yml" ]]; then
            COMPOSE_DIR="${STACK_DIR}"
        fi
    fi

    # Fallback 2: discover active compose project via docker compose ls
    if [[ ! -d "${COMPOSE_DIR}" ]] && command -v docker &>/dev/null; then
        local _grid_cfg
        _grid_cfg="$(docker compose ls --format json 2>/dev/null \
            | grep -o '"ConfigFiles":"[^"]*"' | head -1 \
            | cut -d'"' -f4)"
        if [[ -n "${_grid_cfg}" && -f "${_grid_cfg}" ]]; then
            COMPOSE_DIR="$(dirname "${_grid_cfg}")"
        fi
    fi

    # ENV_FILE: resolve relative to wherever compose was found
    if [[ ! -f "${ENV_FILE}" ]]; then
        if   [[ -f "${COMPOSE_DIR}/.env" ]];         then ENV_FILE="${COMPOSE_DIR}/.env"
        elif [[ -f "${COMPOSE_DIR}/.env.example" ]]; then ENV_FILE="${COMPOSE_DIR}/.env.example"
        fi
    fi
}
