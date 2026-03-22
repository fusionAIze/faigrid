#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Backup Node Installer (Vault)
# ==============================================================================
# Focused on setting up Restic/Rsync targets for Synology or internal storage.
set -euo pipefail

echo "[grid-backup] Initializing backup target..."

# 1. Install Restic
if ! command -v restic &> /dev/null; then
    echo "[grid-backup] Installing restic..."
    if [[ "$(uname -s)" == "Darwin" ]]; then
        brew install restic || echo "[WARN] Homebrew failed. Install restic manually."
    else
        sudo apt-get update -y && sudo apt-get install -y restic
    fi
else
    echo "[SUCCESS] Restic already installed."
fi

# 2. Setup Config
CONFIG_FILE="${SCRIPT_DIR}/_backup_config.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[grid-backup] Specialized configuration not found. Creating from template..."
    cp "${SCRIPT_DIR}/_backup_config.sh.template" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
fi

# 3. Scaffold local vault directory (Default target)
VAULT_DIR="/opt/nexus-vault"
echo "[grid-backup] Scaffolding local vault area..."
sudo mkdir -p "${VAULT_DIR}"
sudo chmod 700 "${VAULT_DIR}"

echo ""
echo "============================================================"
echo "          fusionAIze Grid - Backup Node Provisioning             "
echo "============================================================"
echo "Next Steps:"
echo "  1. Edit ${CONFIG_FILE} to set your Repo and Password."
echo "  2. Initialize the repository: restic init"
echo "  3. For Synology/SFTP, ensure SSH keys are exchanged."
echo "============================================================"
echo ""
echo "[grid-backup] Backup target provisioning complete."
