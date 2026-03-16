#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - Workbench Plugin Uninstaller (All)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd || exit 1)"
# shellcheck source=core/workbench/scripts/_lib.sh
source "${SCRIPT_DIR}/../_lib.sh"

print_header "Uninstalling All Workbench Plugins"

read -r -p "Are you sure you want to remove ALL installed plugins? (y/N): " choice
if [[ ! "$choice" =~ ^[Yy]$ ]]; then
    exit 0
fi

find "${SCRIPT_DIR}/agents" "${SCRIPT_DIR}/clis" "${SCRIPT_DIR}/automation" "${SCRIPT_DIR}/monitoring" -type f -name "*.sh" -print0 | while IFS= read -r -d '' p; do
    info "Removing $(basename "$p")..."
    # Logic to remove binary symlinks if they exist
    BINARY_NAME=$(grep "TOOL_NAME=" "$p" | cut -d'"' -f2 || true)
    if [[ -n "$BINARY_NAME" ]]; then
        sudo rm "/usr/local/bin/${BINARY_NAME}" 2>/dev/null || true
    fi
    rm "$p"
done

success "Full workbench plugin cleanup complete."
