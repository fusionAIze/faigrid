#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${HERE}/_lib.sh"

WIPE_STATE=0
KEEP_TOKEN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wipe-state) WIPE_STATE=1; shift;;
    --keep-token) KEEP_TOKEN=1; shift;;
    *) die "unknown arg: $1";;
  esac
done

is_linux || die "run on core linux host."
require_root

need systemctl
need rm
need install

systemctl stop openclaw.service >/dev/null 2>&1 || true
systemctl disable openclaw.service >/dev/null 2>&1 || true

rm -f /etc/systemd/system/openclaw.service
systemctl daemon-reload || true

rm -f /etc/openclaw/openclaw.env /etc/openclaw/openclaw.token.env

if [[ "${KEEP_TOKEN}" -eq 0 ]]; then
  rm -f /etc/openclaw/secret/gateway.token
fi

if [[ "${WIPE_STATE}" -eq 1 ]]; then
  rm -rf /var/lib/openclaw/.openclaw
fi

echo "OK: uninstalled (wipe_state=${WIPE_STATE} keep_token=${KEEP_TOKEN})"
