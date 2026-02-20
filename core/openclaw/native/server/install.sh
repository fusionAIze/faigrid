#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$HERE/_lib.sh"

need_root

VERSION="2026.2.19-2"
ROTATE_TOKEN=0

usage() {
  cat <<USAGE
Usage:
  sudo ./install.sh [--version X.Y.Z] [--rotate-token]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2;;
    --rotate-token) ROTATE_TOKEN=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "Unknown arg: $1";;
  esac
done

log "Install OpenClaw Native (version=$VERSION rotate_token=$ROTATE_TOKEN)"

ensure_group_user
ensure_dirs
ensure_env_files
ensure_token_file "$ROTATE_TOKEN"

install_openclaw_cli "$VERSION"
install_systemd_unit "$HERE/openclaw.service"
restart_service

log "Done. Verify with: sudo ./verify.sh"
