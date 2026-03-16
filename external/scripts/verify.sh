#!/usr/bin/env bash
set -euo pipefail

echo "[nexus-external] Verifying cloud stack health..."

check_container() {
    if docker ps --format '{{.Names}}' | grep -q "$1"; then
        echo "[SUCCESS] $1 is running."
    else
        echo "[ERROR] $1 is not running."
    fi
}

check_container "nexus-external-n8n"
check_container "nexus-plane-web"

echo "[nexus-external] Verification complete."
