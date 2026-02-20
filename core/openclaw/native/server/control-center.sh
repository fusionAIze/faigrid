#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${HERE}/_lib.sh"

is_linux || die "run on core linux host."
require_root

need systemctl
need journalctl

cmd="${1:-status}"
case "${cmd}" in
  status) systemctl --no-pager -l status openclaw.service ;;
  restart) systemctl restart openclaw.service ;;
  stop) systemctl stop openclaw.service ;;
  start) systemctl start openclaw.service ;;
  logs) journalctl -u openclaw.service -n 200 --no-pager ;;
  follow) journalctl -u openclaw.service -f ;;
  *) die "usage: $0 {status|restart|stop|start|logs|follow}" ;;
esac
