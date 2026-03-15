#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - AI-Native Deployment Wrapper
# ==============================================================================
# This script is designed to be executed by autonomous AI agents (Codex, Claude,
# Gemini) to orchestrate deployments across the 5-node architecture headlessly.
# It requires `jq` and ingests a JSON topology file.

set -euo pipefail

# --- Colors & Styling ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${CYAN}[AI-Deploy]${NC} $1"; }
error() { echo -e "${RED}[AI-Deploy Error]${NC} $1"; exit 1; }
success() { echo -e "${GREEN}[AI-Deploy Success]${NC} $1"; }

if ! command -v jq &> /dev/null; then
    error "jq is strictly required for AI deployment parsing. Please 'apt-get install jq'."
fi

if [[ -z "${1:-}" ]]; then
    error "Usage: $0 <path-to-topology.json>"
fi

TOPOLOGY_FILE="$1"

if [[ ! -f "$TOPOLOGY_FILE" ]]; then
    error "Topology file not found: $TOPOLOGY_FILE"
fi

log "Ingesting AI payload from $TOPOLOGY_FILE..."

# Extract global configuration
GLOBAL_OVERWRITE=$(jq -r '.global.force_overwrite // "false"' "$TOPOLOGY_FILE")
if [[ "$GLOBAL_OVERWRITE" == "true" ]]; then
    log "Global overwrite enforced. Destructive changes will proceed without confirmation."
fi

# Iterate over nodes in the JSON array
NODE_COUNT=$(jq '.nodes | length' "$TOPOLOGY_FILE")
log "Detected $NODE_COUNT target nodes in topology."

for (( i=0; i<NODE_COUNT; i++ )); do
    ROLE=$(jq -r ".nodes[$i].role" "$TOPOLOGY_FILE")
    SSH_TARGET=$(jq -r ".nodes[$i].ssh_target // empty" "$TOPOLOGY_FILE")
    STRATEGY=$(jq -r ".nodes[$i].strategy // 1" "$TOPOLOGY_FILE") # Default to Extend (1)
    
    # Validation
    if [[ "$ROLE" == "null" || -z "$ROLE" ]]; then
        error "Node payload at index $i is missing the 'role' key."
    fi
    
    EXEC_MODE="local"
    if [[ -n "$SSH_TARGET" ]]; then
        EXEC_MODE="remote"
    fi
    
    log "------------------------------------------------------------"
    log "Triggering Sub-Orchestrator for Role: [${ROLE}] on Target: [${SSH_TARGET:-localhost}]"
    
    # Build Universal Installer Command
    INSTALL_CMD=("./install.sh" "--role" "$ROLE" "--strategy" "$STRATEGY")
    
    if [[ "$EXEC_MODE" == "remote" ]]; then
        INSTALL_CMD+=("--mode" "remote" "--target" "$SSH_TARGET")
    else
        INSTALL_CMD+=("--mode" "local")
    fi
    
    if [[ "$GLOBAL_OVERWRITE" == "true" ]]; then
        INSTALL_CMD+=("--yes")
    fi
    
    # Execute
    log "Running: ${INSTALL_CMD[*]}"
    "${INSTALL_CMD[@]}"
    
    # Check Result
    if [[ $? -eq 0 ]]; then
        success "Node [${ROLE}] deployed successfully."
    else
        error "Node [${ROLE}] deployment failed. Agent: please evaluate the stdout/stderr."
    fi
    log "------------------------------------------------------------"
done

success "Full AI Topological Deployment Complete."
