#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
CORE_ROOT="$(cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd)"

# Path resolution: prefer /opt/ but fallback to relative repo path if /opt/ is missing
STACK_DIR="/opt/fusionaize-nexus/core-heart"
if [[ ! -d "${STACK_DIR}" ]]; then
    STACK_DIR="${CORE_ROOT}/heart"
fi

COMPOSE_DIR="${STACK_DIR}/compose"
ENV_FILE="${STACK_DIR}/.env"

# Fallback 1: compose files may live directly in STACK_DIR (no /compose subdir)
if [[ ! -d "${COMPOSE_DIR}" ]]; then
    if [[ -f "${STACK_DIR}/docker-compose.yml" ]] || [[ -f "${STACK_DIR}/compose.yml" ]]; then
        COMPOSE_DIR="${STACK_DIR}"
    fi
fi

# Fallback 2: discover active compose project path via docker compose ls
if [[ ! -d "${COMPOSE_DIR}" ]] && command -v docker &>/dev/null; then
    NEXUS_CONFIG="$(docker compose ls --format json 2>/dev/null \
        | grep -o '"ConfigFiles":"[^"]*"' | head -1 \
        | cut -d'"' -f4)"
    if [[ -n "${NEXUS_CONFIG}" && -f "${NEXUS_CONFIG}" ]]; then
        COMPOSE_DIR="$(dirname "${NEXUS_CONFIG}")"
    fi
fi

# ENV_FILE: resolve relative to wherever compose was found
if [[ ! -f "${ENV_FILE}" ]]; then
    if [[ -f "${COMPOSE_DIR}/.env" ]]; then
        ENV_FILE="${COMPOSE_DIR}/.env"
    elif [[ -f "${COMPOSE_DIR}/.env.example" ]]; then
        ENV_FILE="${COMPOSE_DIR}/.env.example"
    fi
fi

ACTION="${1:-}"

case "$ACTION" in
  start|stop|restart|status|ps|reload)
    if [[ ! -d "${COMPOSE_DIR}" ]]; then
        echo "[ERROR] Compose directory not found: ${COMPOSE_DIR}"
        exit 1
    fi
    cd "${COMPOSE_DIR}" || exit 1
    
    case "$ACTION" in
        start)   docker compose --env-file "${ENV_FILE}" start ;;
        stop)    docker compose --env-file "${ENV_FILE}" stop ;;
        restart) docker compose --env-file "${ENV_FILE}" restart ;;
        status|ps) docker compose --env-file "${ENV_FILE}" ps ;;
        reload)  docker compose --env-file "${ENV_FILE}" up -d --force-recreate ;;
    esac
    ;;
  
  workbench|w)
    WB_CONTROL="${CORE_ROOT}/workbench/scripts/control.sh"
    if [[ -f "${WB_CONTROL}" ]]; then
        bash "${WB_CONTROL}"
    else
        echo "[ERROR] Workbench control not found at ${WB_CONTROL}"
        exit 1
    fi
    ;;

  install)  bash "${SCRIPT_DIR}/install.sh" ;;
  update)   bash "${SCRIPT_DIR}/update.sh" ;;
  verify)   bash "${SCRIPT_DIR}/verify.sh" ;;
  uninstall) bash "${SCRIPT_DIR}/uninstall.sh" ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|reload|workbench|install|update|verify|uninstall}"
    exit 1
    ;;
esac
