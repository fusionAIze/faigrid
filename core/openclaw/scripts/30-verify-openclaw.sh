#!/usr/bin/env bash
set -euo pipefail

echo "[openclaw] status checks"
command -v openclaw >/dev/null && echo "OK: openclaw in PATH" || (echo "ERR: openclaw not found" && exit 1)

echo
echo "[openclaw] gateway status (if available)"
openclaw gateway status || true

echo
echo "[openclaw] doctor (if available)"
openclaw doctor || true
