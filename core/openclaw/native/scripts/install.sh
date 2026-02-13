#!/usr/bin/env bash
set -euo pipefail

echo "[openclaw-native] install (skeleton)"
echo
echo "This script is designed to run on the target host (e.g. nexus-core)."
echo "It will later:"
echo "  1) create system user openclaw"
echo "  2) create dirs (/opt/openclaw, /var/lib/openclaw, /var/log/openclaw)"
echo "  3) fetch/install OpenClaw (official installer or git release)"
echo "  4) place /etc/openclaw/openclaw.env"
echo "  5) install systemd unit + enable service"
echo
echo "TODO: implement once OpenClaw install method is finalized."
