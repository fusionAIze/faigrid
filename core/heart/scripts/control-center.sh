#!/usr/bin/env bash
set -euo pipefail
ACTION="${1:-}"

case "$ACTION" in
  install)  bash "$(dirname "$0")/install.sh" ;;
  update)   bash "$(dirname "$0")/update.sh" ;;
  backup)   bash "$(dirname "$0")/backup.sh" ;;
  restore)  bash "$(dirname "$0")/restore.sh" ;;
  verify)   bash "$(dirname "$0")/verify.sh" ;;
  *)
    echo "Usage: $0 {install|update|backup|restore|verify}"
    exit 1
    ;;
esac
