#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Worker Node Installer (Inference)
# ==============================================================================
# Optimized for macOS (MacBook) and inference-heavy environments.
set -euo pipefail

echo "[grid-worker] Detecting environment..."
OS_TYPE="$(uname -s)"
ARCH_TYPE="$(uname -m)"

if [[ "$OS_TYPE" == "Darwin" ]]; then
    echo "[grid-worker] macOS detected (Architecture: ${ARCH_TYPE})."
    
    # 1. Check for Homebrew
    if ! command -v brew &> /dev/null; then
        echo "[INFO] Homebrew not found. Please install it from https://brew.sh/."
    fi

    # 2. Inference engine (Ollama)
    if ! command -v ollama &> /dev/null; then
        echo "[INFO] Ollama not found. Recommended for local LLM serving on MacBook."
        echo "       Download: https://ollama.com/download/mac"
    else
        echo "[SUCCESS] Ollama detected."
    fi

    # 3. LM Studio CLI (lms) - User Preference
    if ! command -v lms &> /dev/null; then
        echo "[INFO] LM Studio CLI (lms) not found."
        echo "       Install via: https://lmstudio.ai/download"
        echo "       Then run: lms bootstrap"
    else
        echo "[SUCCESS] LM Studio CLI (lms) detected."
    fi

    # 4. Secure Tunneling (Tailscale)
    if ! command -v tailscale &> /dev/null; then
        echo "[INFO] Tailscale not detected. Highly recommended for 'grid-worker' -> 'grid-core' tunnels."
        echo "       Install: brew install tailscale"
    fi

else
    echo "[grid-worker] Linux detected. Standardizing packages..."
    sudo apt-get update -y && sudo apt-get install -y curl jq
    
    if ! command -v ollama &> /dev/null; then
        echo "[grid-worker] Installing Ollama for Linux..."
        curl -fsSL https://ollama.com/install.sh | sh
    fi
fi

echo ""
echo "============================================================"
echo "Qwen 3.5-9B Optimization Hints (8GB MacBook):"
echo "  - Format: GGUF (Strictly Q4_K_M or Q3_K_M recommended)"
echo "  - Memory: Q4 uses ~5.5GB. Minimal headroom left for macOS."
echo "  - Optimizer: Run ./worker/scripts/apple-silicon-optimizations.sh"
echo "  - Context: Limit to 4096 (Ollama: num_ctx 4096)"
echo "  - Engine: Ollama (Metal) is highly recommended for 8GB."
echo "============================================================"
echo ""
echo "[grid-worker] Configuration Note:"
echo "  To bridge this MacBook to Nexus Core, please consult docs/runbooks/tunneling.md"
echo "  For LM Studio: ssh -R 1234:localhost:1234 user@grid-core-ip"
echo "  For Ollama:    ssh -R 11434:localhost:11434 user@grid-core-ip"
echo ""
echo "[grid-worker] Worker node provisioning complete."
