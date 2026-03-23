#!/usr/bin/env bash
set -euo pipefail

echo "[grid-external] Verifying cloud stack health..."

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
    n8n)   check_container "grid-external-n8n" ;;
    plane) check_container "grid-plane-web" ;;
    all)   check_container "grid-external-n8n"; check_container "grid-plane-web" ;;
    *)     echo "Unknown component: ${COMPONENT}"; exit 1 ;;
esac

echo "[grid-external] Verification complete."
