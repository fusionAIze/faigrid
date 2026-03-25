#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="/opt/faigrid/core-heart"
COMPOSE_DIR="${STACK_DIR}/compose"
ENV_FILE="${STACK_DIR}/.env"

echo "[grid-core-heart] Installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg git jq unzip ufw

echo "[grid-core-heart] Installing Docker (Debian official packages)..."
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

echo "[grid-core-heart] Enabling docker..."
sudo systemctl enable --now docker

echo "[grid-core-heart] Applying base security hardening..."
# Calculate relative path to base scripts
BASE_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../base/scripts" &> /dev/null && pwd)"
if [[ -d "${BASE_SCRIPTS_DIR}" ]]; then
    bash "${BASE_SCRIPTS_DIR}/ufw-apply.sh"
    bash "${BASE_SCRIPTS_DIR}/ssh-hardening-apply.sh"
else
    echo "[WARN] Base security scripts not found at ${BASE_SCRIPTS_DIR}"
fi

echo "[grid-core-heart] Creating stack dir: ${STACK_DIR}"
sudo mkdir -p "${STACK_DIR}"
if ! id -u grid > /dev/null 2>&1; then
  echo "[grid-core-heart] Creating system user 'grid'..."
  sudo useradd -m -s /bin/bash grid
fi
sudo chown -R grid:grid "${STACK_DIR}"

echo "[grid-core-heart] Copy compose + env template"
mkdir -p "${COMPOSE_DIR}"
cp -a core/heart/compose/docker-compose.yml "${COMPOSE_DIR}/docker-compose.yml"
if [[ ! -f "${ENV_FILE}" ]]; then
  cp -a core/heart/compose/.env.example "${ENV_FILE}"
  # Auto-generate N8N_ENCRYPTION_KEY so the instance starts correctly on first boot.
  # The key is derived from the existing config volume when one is present (migration),
  # or freshly generated via openssl (clean install).
  if grep -q "CHANGE_ME" "${ENV_FILE}"; then
    _vol_key=""
    _vol_key=$(docker run --rm -v compose_n8n_data:/data alpine \
        sh -c 'cat /data/config 2>/dev/null || true' 2>/dev/null \
        | grep -o '"encryptionKey":"[^"]*"' | cut -d'"' -f4 || true)
    if [[ -n "$_vol_key" ]]; then
      echo "[grid-core-heart] Migrating existing n8n encryption key from volume."
      N8N_KEY="$_vol_key"
    else
      N8N_KEY=$(openssl rand -hex 32)
    fi
    sed -i "s|CHANGE_ME_32+_CHARS_MIN|${N8N_KEY}|" "${ENV_FILE}"
    echo "[grid-core-heart] N8N_ENCRYPTION_KEY set."
  fi
  echo ">> IMPORTANT: edit ${ENV_FILE} and set remaining secrets (POSTGRES_PASSWORD, WEBHOOK_SHARED_SECRET)"
fi

echo "[grid-core-heart] Add grid user to docker group (logout/login required)"
sudo usermod -aG docker grid

echo "[grid-core-heart] Starting stack..."
cd "${COMPOSE_DIR}" || exit 1 || exit
docker compose --env-file "${ENV_FILE}" up -d

echo "[grid-core-heart] Done."
echo "Check: docker ps"
echo "n8n is bound to localhost: http://127.0.0.1:5678"
