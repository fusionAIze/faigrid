#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$ACTION" in
  update)         bash "$DIR/update.sh" ;;
  backup)         bash "$DIR/backup.sh" ;;
  firewall-apply) bash "$DIR/firewall-apply.sh" ;;
  *)
    echo "Usage: $0 {update|backup|firewall-apply}"
    exit 1
    ;;
esac
