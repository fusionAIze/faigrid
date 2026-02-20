#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${HERE}/_lib.sh"

VERSION="2026.2.19-2"
ROTATE_TOKEN=0
SKIP_NPM_INSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2;;
    --rotate-token) ROTATE_TOKEN=1; shift;;
    --skip-npm-install) SKIP_NPM_INSTALL=1; shift;;
    *) die "unknown arg: $1";;
  esac
done

is_linux || die "run on core linux host."
require_root

need install
need sed
need systemctl
need journalctl

PM="$(detect_pm)"
if [[ "${PM}" == "apt" ]]; then
  apt-get update -y
  apt-get install -y ca-certificates curl openssl
fi

need node
need npm

if [[ "${SKIP_NPM_INSTALL}" -eq 0 ]]; then
  npm -g config set prefix /usr/local >/dev/null 2>&1 || true
  npm i -g "openclaw@${VERSION}"
fi

command -v openclaw >/dev/null 2>&1 || die "openclaw CLI not found after npm install"

ensure_user_group "openclaw" "openclaw" "/var/lib/openclaw"

install -d -m 0750 -o root -g openclaw /etc/openclaw/secret

if [[ ! -f /etc/openclaw/secret/gateway.token || "${ROTATE_TOKEN}" -eq 1 ]]; then
  TOKEN="$(random_token)"
  install -m 0640 -o root -g openclaw /dev/null /etc/openclaw/secret/gateway.token
  printf "%s" "${TOKEN}" > /etc/openclaw/secret/gateway.token
fi

if [[ ! -f /etc/openclaw/openclaw.env ]]; then
  install -m 0640 -o root -g openclaw /dev/null /etc/openclaw/openclaw.env
  cat > /etc/openclaw/openclaw.env <<'EOF'
OPENCLAW_GATEWAY_BIND=loopback
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_GATEWAY_AUTH=token
EOF
fi

TOKEN="$(tr -d '\r\n' < /etc/openclaw/secret/gateway.token)"
install -m 0640 -o root -g openclaw /dev/null /etc/openclaw/openclaw.token.env
printf "OPENCLAW_GATEWAY_TOKEN=%s\n" "${TOKEN}" > /etc/openclaw/openclaw.token.env

install -m 0644 -o root -g root "${HERE}/openclaw.service" /etc/systemd/system/openclaw.service
systemctl daemon-reload
systemctl enable --now openclaw.service

echo "OK: installed openclaw@${VERSION}"
