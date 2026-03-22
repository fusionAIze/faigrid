#!/usr/bin/env bash
set -euo pipefail
echo "[grid-worker] Verifying inference engines..."

if command -v ollama &> /dev/null; then
    if ollama list &> /dev/null; then
        echo "[SUCCESS] Ollama is active and reachable."
    else
        echo "[WARN] Ollama is installed but not responding."
    fi
fi

if command -v lms &> /dev/null; then
    if lms status &> /dev/null; then
        echo "[SUCCESS] LM Studio (lms) is active."
    else
        echo "[WARN] LM Studio (lms) is not responding."
    fi
fi

if command -v tailscale &> /dev/null; then
    tailscale status || echo "[INFO] Tailscale installed but not connected."
fi
