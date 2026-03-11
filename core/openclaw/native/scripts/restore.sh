#!/usr/bin/env bash
set -euo pipefail

echo "[openclaw-native] restore is not implemented in this wrapper"
echo "Expected inputs:"
echo "  /var/backups/nexus-core/openclaw/openclaw_YYYY-MM-DD.tar.gz"
echo "  /var/backups/nexus-core/openclaw/openclaw_data_YYYY-MM-DD.tar.gz"
echo
echo "Use the server-side service scripts plus a manual restore procedure."
exit 1
