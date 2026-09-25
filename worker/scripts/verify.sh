#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/worker-env.sh
source "${SCRIPT_DIR}/../lib/worker-env.sh"

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

# llama.cpp: report the ABSOLUTE binary path, not merely CLI presence. A
# non-interactive PATH (sshd forced command, launchd, cron) has no
# /opt/homebrew/bin, so `command -v` finds it interactively but not there.
if LLAMA_SERVER_BIN="$(worker_llama_server_bin)"; then
    echo "[SUCCESS] llama.cpp detected at ${LLAMA_SERVER_BIN}."
else
    echo "[WARN] llama.cpp (llama-server) not found on PATH or in WORKER_BIN_DIRS."
fi

if command -v tailscale &> /dev/null; then
    tailscale status || echo "[INFO] Tailscale installed but not connected."
fi

# Health check: probe the HTTP inference endpoint. The CLI presence checks above
# do not prove the endpoint answers; this does, and it fails loudly when it does
# not instead of reporting a present CLI as a healthy worker.
echo "[grid-worker] Probing inference endpoint: $(worker_health_url)"
if worker_health_check; then
    echo "[SUCCESS] Inference endpoint is answering."
else
    echo "[FAIL] Inference endpoint did not answer."
    exit 1
fi
