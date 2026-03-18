#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_ROOT="$(cd "${SCRIPT_DIR}/../.." &>/dev/null && pwd)"

# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"
resolve_compose_paths

ACTION="${1:-}"

case "$ACTION" in
  start|stop|restart|status|ps|reload)
    if [[ ! -d "${COMPOSE_DIR}" ]]; then
        echo "[ERROR] Compose directory not found: ${COMPOSE_DIR}"
        exit 1
    fi
    cd "${COMPOSE_DIR}" || exit 1

    case "$ACTION" in
        start)     docker compose --env-file "${ENV_FILE}" start ;;
        stop)      docker compose --env-file "${ENV_FILE}" stop ;;
        restart)   docker compose --env-file "${ENV_FILE}" restart ;;
        status|ps) docker compose --env-file "${ENV_FILE}" ps ;;
        reload)    docker compose --env-file "${ENV_FILE}" up -d --force-recreate ;;
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

  install)   bash "${SCRIPT_DIR}/install.sh" ;;
  update)    bash "${SCRIPT_DIR}/update.sh" ;;
  verify)    bash "${SCRIPT_DIR}/verify.sh" ;;
  uninstall) bash "${SCRIPT_DIR}/uninstall.sh" ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|reload|workbench|install|update|verify|uninstall}"
    exit 1
    ;;
esac
