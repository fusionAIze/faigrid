#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-}"

case "$ACTION" in
  start|stop|restart|status|reload)
    sudo systemctl "$ACTION" caddy
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
