#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"

case "$ACTION" in
  start|stop|restart|status)
    echo "[grid-backup] Managing backup timers..."
    if systemctl list-unit-files | grep -q "restic-backup.timer"; then
        sudo systemctl "$ACTION" restic-backup.timer
    else
        echo "[INFO] No backup timers detected."
    fi
    ;;
  install)   bash "$(dirname "$0")/install.sh" ;;
  update)    bash "$(dirname "$0")/update.sh" ;;
  verify)    bash "$(dirname "$0")/verify.sh" ;;
  uninstall) bash "$(dirname "$0")/uninstall.sh" ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|install|update|verify|uninstall}"
    exit 1
    ;;
esac
