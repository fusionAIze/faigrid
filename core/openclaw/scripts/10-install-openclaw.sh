#!/usr/bin/env bash
set -euo pipefail

# Run on Debian host (nexus-core).
# Source: OpenClaw docs show installer script:
#   curl -fsSL https://openclaw.ai/install.sh | bash
#
# This script is a TEMPLATE. It intentionally does not manage secrets.

echo "[openclaw] installing via installer script..."
curl -fsSL https://openclaw.ai/install.sh | bash

echo
echo "[openclaw] next: run onboarding wizard (daemon install):"
echo "  openclaw onboard --install-daemon"
