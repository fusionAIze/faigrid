#!/usr/bin/env bash
set -euo pipefail

# Run on Debian host (nexus-core).
# Docs show:
#   openclaw onboard --install-daemon
# Then:
#   openclaw gateway status
#   openclaw dashboard

echo "[openclaw] onboarding (installs daemon/service if supported)..."
openclaw onboard --install-daemon

echo
echo "[openclaw] check status:"
echo "  openclaw gateway status"
echo
echo "[openclaw] open UI:"
echo "  openclaw dashboard"
