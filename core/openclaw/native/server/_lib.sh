#!/usr/bin/env bash
set -euo pipefail

log() { printf "[1;34m==>[0m %s
" "$*"; }
warn(){ printf "[1;33m!![0m %s
" "$*" >&2; }
die() { printf "[1;31mxx[0m %s
" "$*" >&2; exit 1; }

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Run as root (use sudo)."
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

ensure_group_user() {
  local group="openclaw" user="openclaw" home="/var/lib/openclaw"
  if ! getent group "$group" >/dev/null; then
    log "Creating group: $group"
    groupadd --system "$group"
  fi
  if ! id -u "$user" >/dev/null 2>&1; then
    log "Creating user: $user"
    useradd --system --home "$home" --create-home --shell /usr/sbin/nologin --gid "$group" "$user"
  fi
  mkdir -p "$home"
  chown "$user:$group" "$home"
  chmod 0750 "$home"
}

ensure_dirs() {
  mkdir -p /etc/openclaw/secret
  chown -R root:openclaw /etc/openclaw
  chmod 0750 /etc/openclaw
  chmod 0750 /etc/openclaw/secret
}

ensure_env_files() {
  if [[ ! -f /etc/openclaw/openclaw.env ]]; then
    log "Creating /etc/openclaw/openclaw.env"
    cat > /etc/openclaw/openclaw.env <<EOF
OPENCLAW_GATEWAY_BIND=loopback
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_GATEWAY_AUTH=token
EOF
    chown root:openclaw /etc/openclaw/openclaw.env
    chmod 0640 /etc/openclaw/openclaw.env
  fi
}

write_token_env_from_secret() {
  local token
  token="$(tr -d '\r\n' < /etc/openclaw/secret/gateway.token)"
  [[ -n "$token" ]] || die "Token file empty: /etc/openclaw/secret/gateway.token"
  printf "OPENCLAW_GATEWAY_TOKEN=%s\n" "$token" > /etc/openclaw/openclaw.token.env
  chown root:openclaw /etc/openclaw/openclaw.token.env
  chmod 0640 /etc/openclaw/openclaw.token.env
}

ensure_token_file() {
  local rotate="${1:-0}"
  if [[ "$rotate" == "1" || ! -f /etc/openclaw/secret/gateway.token ]]; then
    log "Generating gateway token"
    umask 0077
    head -c 16 /dev/urandom | xxd -p -c 32 > /etc/openclaw/secret/gateway.token
    chown root:openclaw /etc/openclaw/secret/gateway.token
    chmod 0640 /etc/openclaw/secret/gateway.token
  fi
  write_token_env_from_secret
}

install_openclaw_cli() {
  local version="$1"
  have node || die "node is missing"
  have npm  || die "npm is missing"

  # Ensure global prefix is /usr/local for root installs
  local prefix
  prefix="$(npm prefix -g 2>/dev/null || true)"
  if [[ "$prefix" != "/usr/local" ]]; then
    warn "npm global prefix is '$prefix' (expected /usr/local). Trying to set it for root."
    npm config set prefix /usr/local >/dev/null 2>&1 || true
  fi

  log "Installing openclaw@$version (global)"
  npm i -g "openclaw@${version}"
  have openclaw || die "openclaw not found on PATH after install"
}

install_systemd_unit() {
  local unit_src="$1"
  [[ -f "$unit_src" ]] || die "Missing unit source: $unit_src"

  log "Installing systemd unit -> /etc/systemd/system/openclaw.service"
  cp -f "$unit_src" /etc/systemd/system/openclaw.service
  chmod 0644 /etc/systemd/system/openclaw.service
  systemctl daemon-reload
  systemctl enable openclaw.service >/dev/null
}

restart_service() {
  log "Restarting openclaw.service"
  systemctl restart openclaw.service
}

stop_disable_service() {
  systemctl stop openclaw.service >/dev/null 2>&1 || true
  systemctl disable openclaw.service >/dev/null 2>&1 || true
}

wipe_state() {
  log "Wiping state under /var/lib/openclaw"
  rm -rf /var/lib/openclaw/.openclaw-prod /var/lib/openclaw/.openclaw /var/lib/openclaw/.cache/openclaw 2>/dev/null || true
  mkdir -p /var/lib/openclaw
  chown openclaw:openclaw /var/lib/openclaw
  chmod 0750 /var/lib/openclaw
}
