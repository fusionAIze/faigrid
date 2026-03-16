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

COMPONENT="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd || exit 1)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd || exit 1)"

case "${COMPONENT}" in
    n8n)   check_container "nexus-external-n8n" ;;
    plane) check_container "nexus-plane-web" ;;
    all)   check_container "nexus-external-n8n"; check_container "nexus-plane-web" ;;
    *)     echo "Unknown component: ${COMPONENT}"; exit 1 ;;
esac

echo "[nexus-external] Verification complete."
