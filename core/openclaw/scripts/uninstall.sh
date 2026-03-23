#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
NATIVE_SERVER_DIR="${SCRIPT_DIR}/../native/server"

echo "[grid-openclaw] Routing to native uninstaller..."
cd "${NATIVE_SERVER_DIR}" || exit 1 && sudo ./uninstall.sh
