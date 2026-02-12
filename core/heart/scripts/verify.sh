#!/usr/bin/env bash
set -euo pipefail

echo "[verify] docker:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo
echo "[verify] n8n local check:"
curl -fsS http://127.0.0.1:5678/ >/dev/null && echo "OK: n8n reachable on localhost:5678" || echo "WARN: n8n not reachable"

echo
echo "[verify] disk:"
df -h / | tail -n 1
