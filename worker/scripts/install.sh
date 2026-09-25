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

    ENGINE_FOUND=false

    # 2. Inference engine (Ollama)
    if ! command -v ollama &> /dev/null; then
        echo "[INFO] Ollama not found. Recommended for local LLM serving on MacBook."
        echo "       Download: https://ollama.com/download/mac"
    else
        echo "[SUCCESS] Ollama detected."
        ENGINE_FOUND=true
    fi

    # 3. LM Studio CLI (lms) - User Preference
    if ! command -v lms &> /dev/null; then
        echo "[INFO] LM Studio CLI (lms) not found."
        echo "       Install via: https://lmstudio.ai/download"
        echo "       Then run: lms bootstrap"
    else
        echo "[SUCCESS] LM Studio CLI (lms) detected."
        ENGINE_FOUND=true
    fi

    # 4. llama.cpp (server binary)
    if ! command -v llama-server &> /dev/null; then
        echo "[INFO] llama.cpp not found. Recommended for local LLM serving on MacBook."
        echo "       Install: brew install llama.cpp"
        echo "       Or build from source: https://github.com/ggml-org/llama.cpp"
    else
        echo "[SUCCESS] llama.cpp detected."
        ENGINE_FOUND=true
    fi

    # 5. Secure Tunneling (Tailscale)
    if ! command -v tailscale &> /dev/null; then
        echo "[INFO] Tailscale not detected. Highly recommended for 'grid-worker' -> 'grid-core' tunnels."
        echo "       Install: brew install tailscale"
    fi

    if ! $ENGINE_FOUND; then
        echo "[WARN] No inference engine detected. Install one of: Ollama, LM Studio, or llama.cpp"
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
echo "  - Context: Limit to 4096"
echo "    - llama.cpp: --ctx-size 4096"
echo "    - Ollama:    num_ctx 4096"
echo "  - Engine: llama.cpp or Ollama (Metal) recommended for 8GB."
echo "============================================================"
echo ""
echo "[grid-worker] Configuration Note:"
echo "  To bridge this MacBook to Grid Core, please consult docs/runbooks/tunneling.md"
echo "  For LM Studio: ssh -R 1234:localhost:1234 user@grid-core-ip"
echo "  For Ollama:    ssh -R 11434:localhost:11434 user@grid-core-ip"
echo "  For llama.cpp: ssh -R 8080:localhost:8080 user@grid-core-ip"
echo ""
echo "[grid-worker] Worker node provisioning complete."
