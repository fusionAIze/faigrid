#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - macOS "Inference Mode" Optimizer
# ==============================================================================
# Focus: Freeing up Unified Memory for 8GB M2/M3 hardware.
set -euo pipefail

echo "============================================================"
echo "          Grid Worker - macOS Inference Mode               "
echo "============================================================"

# 1. Memory Pressure Audit
FREE_MEM_GB=$(vm_stat | awk '/Pages free/ {print $3}' | tr -d '.' | awk '{print ($1*4096)/1024/1024/1024}')
echo "[INFO] Current Free Unified Memory: ${FREE_MEM_GB} GB"

if (( $(echo "$FREE_MEM_GB < 3.0" | bc -l) )); then
    echo "[WARN] Low memory detected. Qwen 3.5-9B (Q4) needs ~5.5GB."
    echo "[INFO] Attempting to close background GUI apps..."
    
    # Close common heavy apps (optional/safe list)
    APPS_TO_CLOSE=("Docker" "Slack" "Microsoft Teams" "Discord" "Spotify" "Google Chrome")
    
    for app in "${APPS_TO_CLOSE[@]}"; do
        if pgrep -x "$app" > /dev/null; then
            echo "  - Closing $app..."
            osascript -e "quit app \"$app\"" 2>/dev/null || true
        fi
    done
fi

# 2. Clear Inactive Memory
echo "[INFO] Purging inactive memory (requires sudo)..."
sudo purge

# 3. Model Recommendation
echo ""
echo "------------------------------------------------------------"
echo "Recommended Config for Qwen 3.5-9B (8GB M2):"
echo "  MODEL: qwen3.5:9b-instruct-q4_K_M"
echo "  CONTEXT: 4096 (Keep it low to avoid swap)"
echo "  ENGINE: Ollama (Native Metal)"
echo "------------------------------------------------------------"

echo "[SUCCESS] Inference Mode applied."
