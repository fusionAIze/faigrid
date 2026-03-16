#!/usr/bin/env bash
set -euo pipefail
echo "[nexus-worker] Updating worker components..."

if [[ "$(uname -s)" == "Darwin" ]]; then
    if command -v brew &> /dev/null; then
        brew upgrade ollama || true
    fi
else
    # Linux update
    curl -fsSL https://ollama.com/install.sh | sh
fi

echo "[nexus-worker] Update complete."
