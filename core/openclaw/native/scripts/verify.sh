#!/usr/bin/env bash
set -euo pipefail

echo "[openclaw-native] verify"
echo "- node: $(node -v 2>/dev/null || echo 'missing')"
echo "- npm : $(npm -v 2>/dev/null || echo 'missing')"
echo

if systemctl is-active --quiet openclaw 2>/dev/null; then
  echo "[ok] openclaw service active"
else
  echo "[info] openclaw service not active (yet)"
fi

ss -tulpn | egrep ':3000' || true
