#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
STACK_DIR="/opt/fusionaize-nexus/core-heart"
COMPOSE_DIR="${STACK_DIR}/compose"
ENV_FILE="${STACK_DIR}/.env"

ACTION="${1:-}"

case "$ACTION" in
  start)
    cd "${COMPOSE_DIR}" || exit 1 && docker compose --env-file "${ENV_FILE}" start
    ;;
  stop)
    cd "${COMPOSE_DIR}" || exit 1 && docker compose --env-file "${ENV_FILE}" stop
    ;;
  restart)
    cd "${COMPOSE_DIR}" || exit 1 && docker compose --env-file "${ENV_FILE}" restart
    ;;
  install)  bash "${SCRIPT_DIR}/install.sh" ;;
  update)   bash "${SCRIPT_DIR}/update.sh" ;;
  backup)   bash "${SCRIPT_DIR}/backup.sh" ;;
  restore)  bash "${SCRIPT_DIR}/restore.sh" ;;
  verify)   bash "${SCRIPT_DIR}/verify.sh" ;;
  uninstall) bash "${SCRIPT_DIR}/uninstall.sh" ;;
  *)
    echo "Usage: $0 {start|stop|restart|install|update|backup|restore|verify|uninstall}"
    exit 1
    ;;
esac
