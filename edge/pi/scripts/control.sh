#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-}"

case "$ACTION" in
  start|stop|restart|status|reload)
    if systemctl list-unit-files caddy.service | grep -q 'caddy.service'; then
        sudo systemctl "$ACTION" caddy
    else
        echo "⚠ Unit caddy.service not found. Is Caddy installed?"
        exit 0
    fi
    ;;
  install)   bash "$DIR/install.sh" ;;
  update)    bash "$DIR/update.sh" ;;
  backup)    bash "$DIR/backup.sh" ;;
  verify)    bash "$DIR/verify.sh" ;;
  uninstall) bash "$DIR/uninstall.sh" ;;
  ufw-apply) bash "$DIR/ufw-apply.sh" ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|reload|install|update|backup|verify|uninstall|ufw-apply}"
    exit 1
    ;;
esac
