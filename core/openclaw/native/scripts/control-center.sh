#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$ACTION" in
  install)  bash "$DIR/install.sh" ;;
  update)   bash "$DIR/update.sh" ;;
  backup)   bash "$DIR/backup.sh" ;;
  restore)  bash "$DIR/restore.sh" ;;
  verify)   bash "$DIR/verify.sh" ;;
  push-prod) bash "$DIR/push-prod.sh" ;;
  push-prod-config-only) bash "$DIR/push-prod-config-only.sh" ;;
  *)
    echo "Usage: $0 {install|update|backup|restore|verify|push-prod|push-prod-config-only}"
    exit 1
    ;;
esac
