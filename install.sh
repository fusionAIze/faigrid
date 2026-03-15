#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - Advanced Universal Orchestrator
# Version 0.0.2
# ==============================================================================

set -euo pipefail

# --- Colors & Styling ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "${CYAN}"
cat << "EOF"
  __           _             _  _______          _   _                     
 / _|         (_)           (_)|__   __|        | \ | |                    
| |_ _   _ ___ _  ___  _ __  _    | | ___  _ __ |_  \| | _____  _   _ ___  
|  _| | | / __| |/ _ \| '_ \| |   | |/ _ \| '_ \  | . ` |/ _ \ \/ / | | / __| 
| | | |_| \__ \ | (_) | | | | |   | | (_) | (_) | | |\  |  __/>  <| |_| \__ \
|_|  \__,_|___/_|\___/|_| |_|_|   |_|\___/ \___/  |_| \_|\___/_/\_\\__,_|___/
                                                                           
                   Nexus Labs Advanced Orchestrator                        
EOF
echo -e "${NC}"

# --- Helpers ---
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
prompt() { read -r -p "$(echo -e "${CYAN}$1${NC} ")" "$2"; }
prompt_hidden() { read -r -s -p "$(echo -e "${CYAN}$1${NC} ")" "$2"; echo ""; }

STATE_FILE="$HOME/.nexus-state"
TOPOLOGY_FILE=".env.topology"
CURRENT_ROLE="none"
CURRENT_VERSION="none"

# --- CLI Arguments ---
MODE_CHOICE=""
SSH_TARGET=""
STRATEGY_CHOICE=""
ROLE_NAME=""
ROLE_DIR=""
AUTO_YES="false"
VNC_CHOICE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --mode) MODE_CHOICE="$2"; shift 2 ;;
    --target) SSH_TARGET="$2"; shift 2 ;;
    --strategy) STRATEGY_CHOICE="$2"; shift 2 ;;
    --role) ROLE_NAME="$2"; shift 2 ;;
    --vnc) VNC_CHOICE="y"; shift ;;
    --yes) AUTO_YES="true"; shift ;;
    *) error "Unknown parameter passed: $1"; exit 1 ;;
  esac
done

# --- Hardware Check Functions ---
check_hardware() {
    local target_role=$1
    local mode=$2 # "local" or "remote"
    local ssh_target=$3 # used if remote
    
    info "Performing hardware pre-flight checks for role: ${target_role}..."
    local ncpu
    local mem_kb
    local mem_gb
    
    if [[ "$mode" == "local" ]]; then
        if [[ "$(uname -s)" == "Darwin" ]]; then
            ncpu=$(sysctl -n hw.ncpu)
            mem_kb=$(( $(sysctl -n hw.memsize) / 1024 ))
        else
            ncpu=$(nproc)
            mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        fi
    else
        # Remote execution wrapping
        if ssh -q "$ssh_target" "uname -s" | grep -q 'Darwin'; then
             ncpu=$(ssh -q "$ssh_target" "sysctl -n hw.ncpu")
             mem_kb=$(ssh -q "$ssh_target" "sysctl -n hw.memsize")
             mem_kb=$(( mem_kb / 1024 ))
        else
             ncpu=$(ssh -q "$ssh_target" "nproc")
             # Safe fallback
             mem_kb=$(ssh -q "$ssh_target" "awk '/MemTotal/ {print \$2}' /proc/meminfo || echo 2000000")
        fi
    fi
    
    mem_gb=$(( mem_kb / 1024 / 1024 ))
    info "Detected CPU Cores: ${ncpu}"
    info "Detected RAM: ${mem_gb} GB"
    
    # Requirement Logic
    if [[ "$target_role" == "worker" ]]; then
        if (( mem_gb < 16 )); then
             warning "Role 'worker' usually requires >16GB RAM for local LLMs. You have ${mem_gb}GB. Inference may be extremely slow or fail."
        fi
        if (( ncpu < 4 )); then
             warning "Role 'worker' needs >=4 CPU Cores for efficient prompt processing."
        fi
    elif [[ "$target_role" == "core" ]]; then
        if (( mem_gb < 4 )); then
             warning "Role 'core' runs n8n, OpenClaw, and PostgreSQL. Recommended >=4GB RAM. You have ${mem_gb}GB."
        fi
    fi
    success "Hardware check completed."
}

# --- State Inspection ---
inspect_state() {
    local mode=$1
    local ssh_target=$2
    
    echo ""
    info "Inspecting target state..."
    if [[ "$mode" == "local" ]]; then
        if [[ -f "$STATE_FILE" ]]; then
            # shellcheck disable=SC1090
            source "$STATE_FILE"
            CURRENT_ROLE=${NEXUS_ROLE:-none}
            CURRENT_VERSION=${NEXUS_VERSION:-none}
        fi
    else
        # Verify remotely
         if ssh -q "$ssh_target" "[ -f $STATE_FILE ]"; then
             local remote_state
             remote_state=$(ssh -q "$ssh_target" "cat $STATE_FILE")
             CURRENT_ROLE=$(echo "$remote_state" | grep "NEXUS_ROLE" | cut -d'=' -f2 || echo "none")
             CURRENT_VERSION=$(echo "$remote_state" | grep "NEXUS_VERSION" | cut -d'=' -f2 || echo "none")
         else
             CURRENT_ROLE="none"
         fi
    fi
    
    if [[ "$CURRENT_ROLE" != "none" ]]; then
       success "Detected prior install: Role [${CURRENT_ROLE}], Version [${CURRENT_VERSION}]"
    else
       info "No prior fusionAIze Nexus state detected."
    fi
}


# --- Output Config ---
echo "# Generated by Universal Orchestrator" > "$TOPOLOGY_FILE"

# --- Target Selection ---
if [[ -z "$MODE_CHOICE" ]]; then
    echo ""
    echo -e "${BOLD}Step 1: Target Definition${NC}"
    echo "  1) Local Installation (Execute directly on this machine)"
    echo "  2) Remote Orchestration (Push to another machine via SSH)"
    prompt "Enter orchestrator target (1/2): " MODE_CHOICE
fi

EXEC_MODE=""
if [[ "$MODE_CHOICE" == "2" || "$MODE_CHOICE" == "remote" ]]; then
    EXEC_MODE="remote"
    if [[ -z "$SSH_TARGET" ]]; then
        prompt "Enter SSH configuration string (e.g. pi@192.168.178.10 or user@my-server.com): " SSH_TARGET
    fi
    
    # Pre-flight SSH test
    info "Testing SSH connectivity to ${SSH_TARGET}..."
    if ! ssh -q "$SSH_TARGET" exit; then
        error "SSH connectivity to ${SSH_TARGET} failed. Ensure keys or passwords are correct."
    fi
else
    EXEC_MODE="local"
    info "Local Orchestration selected."
fi

# Detect existing state before allowing mode selection
inspect_state "$EXEC_MODE" "$SSH_TARGET"
echo ""

# --- Execution Strategy Menu ---
if [[ -z "$STRATEGY_CHOICE" ]]; then
    echo -e "${BOLD}Step 2: Execution Strategy${NC}"
    echo "  1) Extend / Update Existing Infra"
    echo "  2) Fresh Install (Overwrite & Destructive)"
    echo "  3) Guided Wizard (with Hardware Validations)"
    prompt "Select operation mode (1/2/3): " STRATEGY_CHOICE
fi

if [[ "$STRATEGY_CHOICE" == "1" ]] && [[ "$CURRENT_ROLE" == "none" ]]; then
     warning "Cannot 'Extend / Update' - no previous installation state was found on the target."
     if [[ "$AUTO_YES" == "true" ]]; then
         error "Non-interactive execution failed: Strategy 1 requested but no prior state exists."
     fi
     STRATEGY_CHOICE="3" # force to wizard
     info "Falling back to Guided Wizard mode."
fi

# --- Role Selection Options ---
ROLE_DIR=""

if [[ "$STRATEGY_CHOICE" == "1" ]]; then
     # For updating, we derive the role from the state unless explicitly overridden
     if [[ -z "$ROLE_NAME" ]]; then
         ROLE_NAME="$CURRENT_ROLE"
     fi
     info "Updating existing infrastructure role: ${ROLE_NAME}"
     case "$ROLE_NAME" in
        "edge") ROLE_DIR="edge/pi" ;;
        "core") ROLE_DIR="core/heart" ;;
        "worker") ROLE_DIR="worker" ;;
        "backup") ROLE_DIR="backup" ;;
        "external") ROLE_DIR="external" ;;
        *) error "Unknown prior role: $ROLE_NAME" ;;
     esac
else
     if [[ -z "$ROLE_NAME" ]]; then
         echo ""
         echo "Select the architectural role to provision:"
         echo "  1) Edge (Ingress)"
         echo "  2) Core (AI Workbench)"
         echo "  3) Worker (Local LLM)"
         echo "  4) Backup (Synology NAS)"
         echo "  5) External (Cloud)"
         prompt "Enter role (1-5): " ROLE_CHOICE

         case "$ROLE_CHOICE" in
             1) ROLE_NAME="edge" ;;
             2) ROLE_NAME="core" ;;
             3) ROLE_NAME="worker" ;;
             4) ROLE_NAME="backup" ;;
             5) ROLE_NAME="external" ;;
             *) error "Invalid choice. Exiting." ;;
         esac
     fi
     
     case "$ROLE_NAME" in
         "edge") ROLE_DIR="edge/pi" ;;
         "core") ROLE_DIR="core/heart" ;;
         "worker") ROLE_DIR="worker" ;;
         "backup") ROLE_DIR="backup" ;;
         "external") ROLE_DIR="external" ;;
         *) error "Invalid role: ${ROLE_NAME}" ;;
     esac
fi

# Safety Warning for Fresh installs
if [[ "$STRATEGY_CHOICE" == "2" ]]; then
     echo ""
     warning "You selected FRESH INSTALL (Overwrite) for [${ROLE_NAME}]."
     warning "This may overwrite critical services (n8n, OpenClaw, Caddy configs) if they already exist."
     if [[ "$AUTO_YES" == "false" ]]; then
         prompt "Are you ABSOLUTELY sure you want to proceed? Type 'overwrite' to confirm: " CONFIRM_OVERWRITE
         if [[ "$CONFIRM_OVERWRITE" != "overwrite" ]]; then
              error "Overwrite not confirmed. Aborting."
         fi
     else
         info "--yes flag detected. Bypassing destructive overwrite confirmation."
     fi
fi

# Hardware Checks for Wizard
if [[ "$STRATEGY_CHOICE" == "3" ]]; then
     check_hardware "$ROLE_NAME" "$EXEC_MODE" "$SSH_TARGET"
fi

# --- Topology writing ---
echo "SERVER_NAME=${ROLE_NAME}-node" >> "$TOPOLOGY_FILE" # Can expand to prompt if needed
echo "ROLE=$ROLE_NAME" >> "$TOPOLOGY_FILE"

if [[ "$ROLE_NAME" == "core" ]]; then
    if [[ -z "$VNC_CHOICE" ]]; then
        echo ""
        prompt "Enable VNC GUI for the AI Workbench? (y/N): " VNC_CHOICE
    fi
    if [[ "$VNC_CHOICE" =~ ^[Yy]$ ]]; then
        echo "ENABLE_VNC=true" >> "$TOPOLOGY_FILE"
    else
        echo "ENABLE_VNC=false" >> "$TOPOLOGY_FILE"
    fi
fi

echo ""
success "Topology configuration staged for deployment."

# --- Deployment Phase ---
if [[ "$EXEC_MODE" == "local" ]]; then
    info "Initiating Local Pipeline for $ROLE_NAME..."
    
    if [[ ! -d "$ROLE_DIR" ]]; then
        warning "Directory $ROLE_DIR not populated in repo. Skipping module execution."
    else
        bash "$ROLE_DIR/scripts/install.sh"
    fi
    
    # Write State
    echo "NEXUS_ROLE=$ROLE_NAME" > "$STATE_FILE"
    echo "NEXUS_VERSION=latest" >> "$STATE_FILE"
    echo "INSTALL_DATE=$(date)" >> "$STATE_FILE"
    success "Saved state to $STATE_FILE"
    
elif [[ "$EXEC_MODE" == "remote" ]]; then
    info "Initiating Remote Pipeline to $SSH_TARGET..."
    
    # 1. Create a remote temp directory
    ssh -q "$SSH_TARGET" "mkdir -p /tmp/nexus-install"
    
    # 2. SCP payload
    info "Transferring payload to target (ignoring git/node_modules)..."
    rsync -avz --exclude='.git' --exclude='node_modules' ./ "$SSH_TARGET:/tmp/nexus-install/" > /dev/null
    
    # 3. SCP the topology config
    scp "$TOPOLOGY_FILE" "${SSH_TARGET}:/tmp/nexus-install/" > /dev/null
    
    # 4. Trigger remote script & generate state file
    info "Executing remote install payload..."
    ssh -t "$SSH_TARGET" "cd /tmp/nexus-install && bash $ROLE_DIR/scripts/install.sh; echo \"NEXUS_ROLE=$ROLE_NAME\" > ~/.nexus-state; echo \"NEXUS_VERSION=latest\" >> ~/.nexus-state"
    
    success "Remote deployment complete. View ~/.nexus-state on target."
fi

echo ""
success "Nexus Labs Orchestration Phase Complete!"
