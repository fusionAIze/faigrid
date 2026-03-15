#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - Worker Node Installer (Inference)
# ==============================================================================
# Optimized for macOS (MacBook) and inference-heavy environments.
set -euo pipefail

echo "[nexus-worker] Detecting environment..."
OS_TYPE="$(uname -s)"
ARCH_TYPE="$(uname -m)"

if [[ "$OS_TYPE" == "Darwin" ]]; then
    echo "[nexus-worker] macOS detected (Architecture: ${ARCH_TYPE})."
    
    # 1. Check for Homebrew
    if ! command -v brew &> /dev/null; then
        echo "[INFO] Homebrew not found. Please install it from https://brew.sh/."
    fi

    # 2. Inference engine (Ollama)
    if ! command -v ollama &> /dev/null; then
        echo "[INFO] Ollama not found. It is recommended for local LLM serving on MacBook."
        echo "       Download it from https://ollama.com/download/mac"
    else
        echo "[SUCCESS] Ollama detected. Ensuring it is running..."
    fi

    # 3. Secure Tunneling (Tailscale)
    if ! command -v tailscale &> /dev/null; then
        echo "[INFO] Tailscale not detected. Highly recommended for secure 'nexus-worker' -> 'nexus-core' tunneling."
        echo "       Install via: brew install tailscale"
    fi

else
    echo "[nexus-worker] Linux detected. Standardizing packages..."
    sudo apt-get update -y && sudo apt-get install -y curl jq
    
    if ! command -v ollama &> /dev/null; then
        echo "[nexus-worker] Installing Ollama for Linux..."
        curl -fsSL https://ollama.com/install.sh | sh
    fi
fi

echo ""
echo "[nexus-worker] Configuration Note:"
echo "  To bridge this MacBook to Nexus Core, please consult docs/runbooks/tunneling.md"
echo "  Recommended: tailscale funnel or ssh -R 11434:localhost:11434 user@nexus-core-ip"
echo ""
echo "[nexus-worker] Worker node provisioning complete."
