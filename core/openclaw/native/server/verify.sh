#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${HERE}/_lib.sh"

is_linux || die "run on core linux host."
require_root

need systemctl
need ss
need openclaw

echo "== openclaw version"
openclaw --version || true
echo

echo "== service status"
systemctl --no-pager -l status openclaw.service || true
echo

echo "== ExecStart"
systemctl show openclaw.service -p ExecStart --no-pager || true
echo

echo "== listening sockets (18789)"
ss -lntp | egrep ':(18789)\b' || true
echo

echo "== token file perms"
stat -c '%A %U:%G %n' /etc/openclaw/secret/gateway.token || true
stat -c '%A %U:%G %n' /etc/openclaw/openclaw.env || true
stat -c '%A %U:%G %n' /etc/openclaw/openclaw.token.env || true
