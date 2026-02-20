#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$DIR/_lib.sh"

need_root

WIPE_STATE=0
KEEP_TOKEN=0
REMOVE_NPM=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wipe-state) WIPE_STATE=1; shift ;;
    --keep-token) KEEP_TOKEN=1; shift ;;
    --remove-npm) REMOVE_NPM=1; shift ;;
    -h|--help)
      cat <<'H'
Usage: sudo ./uninstall.sh [--wipe-state] [--keep-token] [--remove-npm]

--wipe-state  Remove OpenClaw state dirs under /var/lib/openclaw
--keep-token  Keep /etc/openclaw/secret/gateway.token (default: remove)
--remove-npm  Also uninstall global npm package openclaw
H
      exit 0
      ;;
    *) die "Unknown arg: $1" ;;
  esac
done

log "Stopping + disabling service"
stop_disable_service

log "Removing systemd unit"
rm -f /etc/systemd/system/openclaw.service
systemctl daemon-reload
systemctl reset-failed openclaw.service >/dev/null 2>&1 || true

log "Removing env files"
rm -f /etc/openclaw/openclaw.env /etc/openclaw/openclaw.token.env || true

if [[ "$KEEP_TOKEN" -eq 1 ]]; then
  log "Keeping token: /etc/openclaw/secret/gateway.token"
else
  log "Removing token: /etc/openclaw/secret/gateway.token"
  rm -f /etc/openclaw/secret/gateway.token || true
fi

if [[ "$WIPE_STATE" -eq 1 ]]; then
  wipe_state
else
  log "Keeping state (skip --wipe-state)"
fi

if [[ "$REMOVE_NPM" -eq 1 ]]; then
  if have npm; then
    log "Uninstalling npm global openclaw"
    npm rm -g openclaw >/dev/null 2>&1 || true
  fi
fi

log "Done."
