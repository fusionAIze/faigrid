#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${HERE}/_lib.sh"

VERSION="2026.2.19-2"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2;;
    *) die "unknown arg: $1";;
  esac
done

is_linux || die "run on core linux host."
require_root
need npm
need systemctl

npm i -g "openclaw@${VERSION}"
systemctl restart openclaw.service
echo "OK: updated openclaw@${VERSION}"
