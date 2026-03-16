#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - Backup Node Installer (Vault)
# ==============================================================================
# Focused on setting up Restic/Rsync targets for Synology or internal storage.
set -euo pipefail

echo "[nexus-backup] Initializing backup target..."

# 1. Install Restic
if ! command -v restic &> /dev/null; then
    echo "[nexus-backup] Installing restic..."
    if [[ "$(uname -s)" == "Darwin" ]]; then
        brew install restic || echo "[WARN] Homebrew failed. Install restic manually."
    else
        sudo apt-get update -y && sudo apt-get install -y restic
    fi
else
    echo "[SUCCESS] Restic already installed."
fi

# 2. Scaffold local vault directory
VAULT_DIR="/opt/nexus-vault"
echo "[nexus-backup] Scaffolding vault at ${VAULT_DIR}..."
sudo mkdir -p "${VAULT_DIR}"
sudo chmod 700 "${VAULT_DIR}"

echo ""
echo "[nexus-backup] Manual Step Required for Synology:"
echo "  1. Ensure SSH is enabled on your Synology NAS."
echo "  2. Create a shared folder named 'nexus-backups'."
echo "  3. Initialize your restic repository: "
echo "     restic -r sftp:user@synology-ip:/volume1/nexus-backups init"
echo ""
echo "[nexus-backup] Backup target provisioning complete."
