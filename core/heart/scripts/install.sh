#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="/opt/fusionaize-nexus/core-heart"
COMPOSE_DIR="${STACK_DIR}/compose"
ENV_FILE="${STACK_DIR}/.env"

echo "[nexus-core-heart] Installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg git jq unzip ufw

echo "[nexus-core-heart] Installing Docker (Debian official packages)..."
# Debian repo docker is fine, but many prefer Docker CE. We'll use Docker CE.
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[nexus-core-heart] Enabling docker..."
sudo systemctl enable --now docker

echo "[nexus-core-heart] Creating stack dir: ${STACK_DIR}"
sudo mkdir -p "${STACK_DIR}"
if ! id -u nexus > /dev/null 2>&1; then
  echo "[nexus-core-heart] Creating system user 'nexus'..."
  sudo useradd -m -s /bin/bash nexus
fi
sudo chown -R nexus:nexus "${STACK_DIR}"

echo "[nexus-core-heart] Copy compose + env template"
mkdir -p "${COMPOSE_DIR}"
cp -a core/heart/compose/docker-compose.yml "${COMPOSE_DIR}/docker-compose.yml"
if [[ ! -f "${ENV_FILE}" ]]; then
  cp -a core/heart/compose/.env.example "${ENV_FILE}"
  echo ">> IMPORTANT: edit ${ENV_FILE} and set real secrets (N8N_ENCRYPTION_KEY, POSTGRES_PASSWORD, WEBHOOK_SHARED_SECRET)"
fi

echo "[nexus-core-heart] Add nexus user to docker group (logout/login required)"
sudo usermod -aG docker nexus

echo "[nexus-core-heart] Starting stack..."
cd "${COMPOSE_DIR}" || exit
docker compose --env-file "${ENV_FILE}" up -d

echo "[nexus-core-heart] Done."
echo "Check: docker ps"
echo "n8n is bound to localhost: http://127.0.0.1:5678"
