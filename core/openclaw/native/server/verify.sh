#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$HERE/_lib.sh"

need_root

log "openclaw version"
if have openclaw; then
  openclaw --version || true
else
  warn "openclaw CLI not found"
fi

log "service status"
systemctl --no-pager status openclaw.service || true

log "listening sockets (18789)"
ss -lntp | egrep ':(18789)\b' || true

log "token + perms"
ls -la /etc/openclaw/secret/gateway.token /etc/openclaw/openclaw.env /etc/openclaw/openclaw.token.env 2>/dev/null || true

log "ExecStart"
systemctl show openclaw.service -p ExecStart --no-pager || true
