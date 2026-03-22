#!/usr/bin/env bash
set -euo pipefail
echo "[grid-worker] Uninstalling worker components..."
echo "Manual step: Please remove Ollama or LM Studio apps if installed via GUI."
if [[ "$(uname -s)" != "Darwin" ]]; then
    sudo systemctl stop ollama || true
    sudo systemctl disable ollama || true
fi
echo "[grid-worker] Uninstallation complete (minimal)."
