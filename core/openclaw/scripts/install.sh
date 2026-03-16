#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
NATIVE_SERVER_DIR="${SCRIPT_DIR}/../native/server"

echo "[nexus-openclaw] Routing to native installer..."
cd "${NATIVE_SERVER_DIR}" || exit 1 && sudo ./install.sh --version 2026.2.19-2
