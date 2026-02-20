#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$HERE/_lib.sh"

need_root

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  die "Usage: sudo ./update.sh <openclaw-version>   (example: sudo ./update.sh 2026.2.19-2)"
fi

install_openclaw_cli "$VERSION"
restart_service
log "Updated to openclaw@$VERSION"
