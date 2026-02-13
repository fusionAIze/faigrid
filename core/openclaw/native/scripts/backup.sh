#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%F)"
DEST="/var/backups/nexus-core/openclaw"
mkdir -p "$DEST"

echo "[openclaw-native] backup -> $DEST/openclaw_${TS}.tar.gz"
sudo tar -czf "$DEST/openclaw_${TS}.tar.gz" \
  /etc/openclaw 2>/dev/null || true

# Data dirs might not exist yet (skeleton-friendly)
sudo tar -czf "$DEST/openclaw_data_${TS}.tar.gz" \
  /var/lib/openclaw /var/log/openclaw 2>/dev/null || true

ls -lah "$DEST" || true
echo "[openclaw-native] done"
