#!/usr/bin/env bash
set -euo pipefail
echo "[nexus-worker] Uninstalling worker components..."
echo "Manual step: Please remove Ollama or LM Studio apps if installed via GUI."
if [[ "$(uname -s)" != "Darwin" ]]; then
    sudo systemctl stop ollama || true
    sudo systemctl disable ollama || true
fi
echo "[nexus-worker] Uninstallation complete (minimal)."
