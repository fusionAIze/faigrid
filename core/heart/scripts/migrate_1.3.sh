#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - 1.3.0 Legacy Migration
# To be removed in Version 1.4.0
# ==============================================================================

set -euo pipefail

# Helper to log locally without importing the whole UI lib
log_mig() { echo -e "\033[38;2;196;217;0m[MIGRATION]\033[0m $1"; }

migrate_from_nexus_to_grid() {
    local legacy_state="$HOME/.grid-state"
    local grid_state="$HOME/.grid-state"
    
    local legacy_config="$HOME/.config/faigrid"
    local grid_config="$HOME/.config/faigrid"

    local legacy_local_reg=".nexus"
    local grid_local_reg=".faigrid"

    # Quick exit if already migrated or no legacy state exists
    if [[ ! -f "$legacy_state" ]]; then return 0; fi
    if [[ -f "$grid_state" ]]; then return 0; fi

    log_mig "Legacy fusionAIze Grid (v0.x - 1.2.x) state detected. Initiating automatic migration..."

    # 1. State File Rename
    log_mig "Migrating state file ($legacy_state -> $grid_state)..."
    mv "$legacy_state" "$grid_state"
    sed -i.bak 's/GRID_ROLE/GRID_ROLE/g' "$grid_state" || true
    sed -i.bak 's/GRID_VERSION/GRID_VERSION/g' "$grid_state" || true
    sed -i.bak 's/grid-core/grid-core/g' "$grid_state" || true
    sed -i.bak 's/grid-edge/grid-edge/g' "$grid_state" || true
    sed -i.bak 's/grid-worker/grid-worker/g' "$grid_state" || true
    rm -f "${grid_state}.bak"

    # 2. Config Folder Rename (Environment Keys)
    if [[ -d "$legacy_config" ]]; then
        log_mig "Migrating configuration directory ($legacy_config -> $grid_config)..."
        mkdir -p "$(dirname "$grid_config")"
        mv "$legacy_config" "$grid_config"
        
        # Rename internal env file
        if [[ -f "${grid_config}/grid.env" ]]; then
            mv "${grid_config}/grid.env" "${grid_config}/grid.env"
        fi
        
        # Patch .bashrc hook reference safely
        if grep -q "nexus/grid.env" "$HOME/.bashrc" 2>/dev/null; then
            log_mig "Patching ~/.bashrc hook variables..."
            sed -i.bak 's/nexus\/grid.env/faigrid\/grid.env/g' "$HOME/.bashrc" || true
            sed -i.bak 's/fusionAIze Grid/fusionAIze Grid/g' "$HOME/.bashrc" || true
            rm -f "${HOME}/.bashrc.bak"
        fi
    fi

    # 3. Local Registry Migration
    if [[ -d "$legacy_local_reg" ]]; then
        log_mig "Migrating local execution registry ($legacy_local_reg -> $grid_local_reg)..."
        mv "$legacy_local_reg" "$grid_local_reg"
        
        # Rename internal state files
        find "$grid_local_reg" -type f -name "nexus-*.state" | while read -r statefile; do
            new_name=$(echo "$statefile" | sed 's/nexus-/grid-/')
            mv "$statefile" "$new_name"
        done
        
        # Patch internal registry variables
        find "$grid_local_reg" -type f -name "*.state" -exec sed -i.bak 's/GRID_ROLE/GRID_ROLE/g' {} + || true
        find "$grid_local_reg" -type f -name "*.state" -exec sed -i.bak 's/nexus-/grid-/g' {} + || true
        find "$grid_local_reg" -type f -name "*.state.bak" -delete 2>/dev/null || true
    fi

    log_mig "Migration perfectly completed. Welcome to faigrid!"
    echo ""
}

# Auto-execute if run as a script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    migrate_from_nexus_to_grid
fi
