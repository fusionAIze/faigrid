#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
NATIVE_SERVER_DIR="${SCRIPT_DIR}/../native/server"

ACTION="${1:-}"

case "$ACTION" in
  start|stop|restart|status)
    sudo systemctl "$ACTION" openclaw
    ;;
  install)  bash "${SCRIPT_DIR}/install.sh" ;;
  update)   bash "${SCRIPT_DIR}/update.sh" ;;
  verify)   bash "${SCRIPT_DIR}/verify.sh" ;;
  uninstall) bash "${SCRIPT_DIR}/uninstall.sh" ;;
  onboard)  bash "${SCRIPT_DIR}/onboard.sh" ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|install|update|verify|uninstall|onboard}"
    exit 1
    ;;
esac
