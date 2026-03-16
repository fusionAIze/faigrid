#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - External Role Installer (Cloud)
# ==============================================================================
set -euo pipefail

COMPONENT="${1:-all}" # n8n, plane, or all
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "[nexus-external] Initializing cloud stack (Component: ${COMPONENT})..."

# 1. Ensure global external network exists
if ! docker network ls | grep -q "nexus_external_net"; then
    echo "[nexus-external] Creating global external network..."
    docker network create nexus_external_net
fi

# 2. Component Installation
install_n8n() {
    echo "[nexus-external] Installing n8n..."
    local n8n_dir="${STACK_DIR}/compose/n8n"
    if [[ ! -f "${n8n_dir}/.env" ]]; then
        cp "${n8n_dir}/.env.example" "${n8n_dir}/.env" || echo "Please create ${n8n_dir}/.env"
    fi
    docker compose -f "${n8n_dir}/docker-compose.yml" up -d
}

install_plane() {
    echo "[nexus-external] Installing Plane.so..."
    local plane_dir="${STACK_DIR}/compose/plane"
    if [[ ! -f "${plane_dir}/.env" ]]; then
        echo "PLANE_DB_PASSWORD=$(openssl rand -hex 16)" > "${plane_dir}/.env"
        echo "PLANE_HOST=plane.example.com" >> "${plane_dir}/.env"
    fi
    docker compose -f "${plane_dir}/docker-compose.yml" up -d
}

case "${COMPONENT}" in
    n8n)   install_n8n ;;
    plane) install_plane ;;
    all)   install_n8n; install_plane ;;
    *)     echo "Unknown component: ${COMPONENT}"; exit 1 ;;
esac

echo "[nexus-external] Installation phase complete."
