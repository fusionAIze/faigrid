#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
NATIVE_SERVER_DIR="${SCRIPT_DIR}/../native/server"

echo "[nexus-openclaw] Routing to native updater..."
cd "${NATIVE_SERVER_DIR}" || exit 1 && sudo ./update.sh
