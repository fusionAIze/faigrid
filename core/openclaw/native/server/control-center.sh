#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$HERE/_lib.sh"

need_root

cmd="${1:-help}"

case "$cmd" in
  status) systemctl --no-pager status openclaw.service;;
  restart) systemctl restart openclaw.service; systemctl --no-pager status openclaw.service;;
  stop) systemctl stop openclaw.service;;
  start) systemctl start openclaw.service;;
  logs) journalctl -u openclaw.service -n 200 --no-pager;;
  tail) journalctl -u openclaw.service -f;;
  verify) "$HERE/verify.sh";;
  rotate-token)
    ensure_dirs
    ensure_token_file 1
    systemctl restart openclaw.service
    log "Rotated token + restarted service"
    ;;
  help|*)
    cat <<EOF
Usage: sudo ./control-center.sh <command>

Commands:
  status | start | stop | restart
  logs   | tail
  verify
  rotate-token
EOF
    ;;
esac
