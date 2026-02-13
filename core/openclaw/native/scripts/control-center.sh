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
  *)
    echo "Usage: $0 {install|update|backup|restore|verify}"
    exit 1
    ;;
esac
