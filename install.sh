#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - Advanced Universal Orchestrator
# Version 2.0.0
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
DIM='\033[2m'

echo -e "${CYAN}"
cat << "EOF"
   __           _                      _____           _   _                       _           _         
  / _|         (_)               /\   |_   _|         | \ | |                     | |         | |        
 | |_ _   _ ___ _  ___  _ __    /  \    | |  _______  |  \| | _____  ___   _ ___  | |     __ _| |__  ___ 
 |  _| | | / __| |/ _ \| '_ \  / /\ \   | | |_  / _ \ | . ` |/ _ \ \/ / | | / __| | |    / _` | '_ \/ __|
 | | | |_| \__ \ | (_) | | | |/ ____ \ _| |_ / /  __/ | |\  |  __/>  <| |_| \__ \ | |___| (_| | |_) \__ \
 |_|  \__,_|___/_|\___/|_| |_/_/    \_\_____/___\___| |_| \_|\___/_/\_\\__,_|___/ |______\__,_|_.__/|___/
                                                                                                         
EOF
echo -e "${NC}"
echo -e "${DIM}  Sovereign AI Infrastructure — Advanced Universal Orchestrator v2.0${NC}"
echo ""

# --- Helpers ---
info()    { echo -e "  ${BLUE}ℹ${NC}  $1"; }
success() { echo -e "  ${GREEN}✔${NC}  $1"; }
warning() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
error()   { echo -e "  ${RED}✘${NC}  $1"; exit 1; }
divider() { echo -e "  ${DIM}──────────────────────────────────────────────────────${NC}"; }

prompt() {
    read -r -p "$(echo -e "  ${CYAN}▸${NC} $1")" "$2"
}

prompt_hidden() {
    read -r -s -p "$(echo -e "  ${CYAN}▸${NC} $1")" "$2"
    echo ""
}

STATE_FILE="$HOME/.nexus-state"
TOPOLOGY_FILE=".env.topology"
CURRENT_ROLE="none"
CURRENT_VERSION="none"

# --- CLI Arguments ---
AUTO_YES="false"
VNC_CHOICE=""
ROLE_CHOICE=""
ACTION_NAME=""
MODE_CHOICE=""
SSH_TARGET=""
ROLE_NAME=""
BOOTSTRAP_MODE="false"
COMPONENT_NAME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --mode)      MODE_CHOICE="$2"; shift 2 ;;
    --target)    SSH_TARGET="$2"; shift 2 ;;
    --role)      ROLE_NAME="$2"; shift 2 ;;
    --action)    ACTION_NAME="$2"; shift 2 ;;
    --component) COMPONENT_NAME="$2"; shift 2 ;;
    --vnc)       VNC_CHOICE="y"; shift ;;
    --yes)       AUTO_YES="true"; shift ;;
    --bootstrap) BOOTSTRAP_MODE="true"; shift ;;
    *) error "Unknown parameter passed: $1" ;;
  esac
done

# --- Hardware Check Functions ---
check_hardware() {
    local target_role=$1
    local mode=$2
    local ssh_target=$3

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
        if ssh -q "$ssh_target" "uname -s" | grep -q 'Darwin'; then
             ncpu=$(ssh -q "$ssh_target" "sysctl -n hw.ncpu")
             mem_kb=$(ssh -q "$ssh_target" "sysctl -n hw.memsize")
             mem_kb=$(( mem_kb / 1024 ))
        else
             ncpu=$(ssh -q "$ssh_target" "nproc")
             mem_kb=$(ssh -q "$ssh_target" "awk '/MemTotal/ {print \$2}' /proc/meminfo || echo 2000000")
        fi
    fi

    mem_gb=$(( mem_kb / 1024 / 1024 ))
    info "Detected CPU Cores: ${ncpu}"
    info "Detected RAM: ${mem_gb} GB"

    if [[ "$target_role" == "worker" ]]; then
        if (( mem_gb < 16 )); then
             warning "Role 'worker' usually requires >16GB RAM for local LLMs. You have ${mem_gb}GB."
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

    if [[ "$mode" == "local" ]]; then
        if [[ -f "$STATE_FILE" ]]; then
            # shellcheck disable=SC1090
            source "$STATE_FILE"
            CURRENT_ROLE=${NEXUS_ROLE:-none}
            CURRENT_VERSION=${NEXUS_VERSION:-none}
        fi
    else
        if ssh -q "$ssh_target" "[ -f \"$STATE_FILE\" ]"; then
             local remote_state
             remote_state=$(ssh -q "$ssh_target" "cat \"$STATE_FILE\"")
             CURRENT_ROLE=$(echo "$remote_state" | grep "NEXUS_ROLE" | cut -d'=' -f2 || echo "none")
             CURRENT_VERSION=$(echo "$remote_state" | grep "NEXUS_VERSION" | cut -d'=' -f2 || echo "none")
        else
             CURRENT_ROLE="none"
        fi
    fi
}

# --- Write State ---
write_state() {
    local mode=$1
    local ssh_target=$2
    local role=$3

    if [[ "$mode" == "local" ]]; then
        echo "NEXUS_ROLE=$role" > "$STATE_FILE"
        echo "NEXUS_VERSION=latest" >> "$STATE_FILE"
        echo "INSTALL_DATE=$(date)" >> "$STATE_FILE"
        success "Saved state to ${STATE_FILE}"
    else
        ssh -q "$ssh_target" "echo 'NEXUS_ROLE=$role' > \"\$HOME/.nexus-state\"; \
            echo 'NEXUS_VERSION=latest' >> \"\$HOME/.nexus-state\"; \
            echo 'INSTALL_DATE=$(date)' >> \"\$HOME/.nexus-state\""
        success "Saved remote state to ~/${ssh_target}:~/.nexus-state"
    fi
}

# --- Role Resolver ---
resolve_role_dir() {
    local role=$1
    case "$role" in
        "edge")     echo "edge/pi" ;;
        "core")     echo "core/heart" ;;
        "worker")   echo "worker" ;;
        "backup")   echo "backup" ;;
        "external") echo "external" ;;
        *) error "Unknown role: $role" ;;
    esac
}

# ==============================================================================
# STEP 1: TARGET DEFINITION
# ==============================================================================
divider
echo -e "  ${BOLD}Step 1 │ Target Definition${NC}"
divider

if [[ -z "$MODE_CHOICE" ]]; then
    echo ""
    echo "  How are you deploying?"
    echo ""
    echo -e "    ${BOLD}1)${NC}  On-Node     ${DIM}— I am logged into the target node right now${NC}"
    echo -e "    ${BOLD}2)${NC}  Remote Push  ${DIM}— Push to a remote node via SSH from this workstation${NC}"
    echo ""
    prompt "Select mode (1/2): " MODE_CHOICE
fi

EXEC_MODE=""
if [[ "$MODE_CHOICE" == "2" || "$MODE_CHOICE" == "remote" ]]; then
    EXEC_MODE="remote"
    if [[ -z "$SSH_TARGET" ]]; then
        echo ""
        prompt "SSH target (e.g. nexus@192.168.178.10): " SSH_TARGET
    fi

    info "Testing SSH connectivity to ${SSH_TARGET}..."
    if ! ssh -q "$SSH_TARGET" exit; then
        error "SSH connectivity to ${SSH_TARGET} failed. Ensure keys or passwords are correct."
    fi
    success "Connected to ${SSH_TARGET}."
else
    EXEC_MODE="local"
    success "On-Node mode: this machine is the target."
fi

# Detect existing state
inspect_state "$EXEC_MODE" "$SSH_TARGET"
echo ""

if [[ "$CURRENT_ROLE" != "none" ]]; then
    success "Detected existing node: Role [${BOLD}${CURRENT_ROLE}${NC}], Version [${CURRENT_VERSION}]"
else
    info "No prior Nexus state detected on this target."
fi

# ==============================================================================
# BOOTSTRAP MODE: Register an existing node without running install scripts
# ==============================================================================
if [[ "$BOOTSTRAP_MODE" == "true" ]]; then
    echo ""
    divider
    echo -e "  ${BOLD}Bootstrap Mode${NC}"
    divider
    echo ""
    info "Registering an existing node without executing install scripts."

    if [[ -z "$ROLE_NAME" ]]; then
        echo ""
        echo -e "    ${BOLD}1)${NC}  nexus-edge       TLS ingress, reverse proxy, DNS"
        echo -e "    ${BOLD}2)${NC}  nexus-core       AI Workbench (n8n, OpenClaw, PG)"
        echo -e "    ${BOLD}3)${NC}  nexus-worker     Local LLM inference (Ollama/LMS)"
        echo -e "    ${BOLD}4)${NC}  nexus-backup     Offsite vault (Synology, S3, etc.)"
        echo -e "    ${BOLD}5)${NC}  nexus-external   Cloud extension (PM, ext. n8n)"
        echo ""
        prompt "Which role does this node serve? (1-5): " ROLE_CHOICE
        case "$ROLE_CHOICE" in
            1) ROLE_NAME="edge" ;;
            2) ROLE_NAME="core" ;;
            3) ROLE_NAME="worker" ;;
            4) ROLE_NAME="backup" ;;
            5) ROLE_NAME="external" ;;
            *) error "Invalid choice." ;;
        esac
    fi

    write_state "$EXEC_MODE" "$SSH_TARGET" "$ROLE_NAME"
    echo ""
    success "Node bootstrapped as [${BOLD}${ROLE_NAME}${NC}]. Future runs will detect this role automatically."
    exit 0
fi

# ==============================================================================
# STEP 2: NODE ROLE SELECTION
# ==============================================================================
echo ""
divider
echo -e "  ${BOLD}Step 2 │ Node Role${NC}"
divider

if [[ -z "$ROLE_NAME" ]]; then
    if [[ "$CURRENT_ROLE" != "none" ]]; then
        # Existing node detected — offer to keep or change
        echo ""
        echo -e "  This target is already registered as ${BOLD}${CURRENT_ROLE}${NC}."
        prompt "Keep this role? (Y/n): " KEEP_ROLE
        if [[ "${KEEP_ROLE:-Y}" =~ ^[Yy]$ || -z "${KEEP_ROLE:-}" ]]; then
            ROLE_NAME="$CURRENT_ROLE"
        fi
    fi

    if [[ -z "$ROLE_NAME" ]]; then
        echo ""
        echo "  Select the architectural role to provision:"
        echo ""
        echo -e "    ${BOLD}1)${NC}  nexus-edge       ${DIM}TLS ingress, reverse proxy, firewall, DNS${NC}"
        echo -e "    ${BOLD}2)${NC}  nexus-core       ${DIM}AI Workbench — n8n, OpenClaw, Postgres, Redis${NC}"
        echo -e "    ${BOLD}3)${NC}  nexus-worker     ${DIM}Local LLM inference — Ollama, LM Studio${NC}"
        echo -e "    ${BOLD}4)${NC}  nexus-backup     ${DIM}Offsite storage vault — Synology, S3, Restic${NC}"
        echo -e "    ${BOLD}5)${NC}  nexus-external   ${DIM}Cloud extension — ext. n8n, Plane PM${NC}"
        echo ""
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
fi

ROLE_DIR="$(resolve_role_dir "$ROLE_NAME")"
success "Target role: ${BOLD}${ROLE_NAME}${NC} (${ROLE_DIR})"

# ==============================================================================
# STEP 3: ACTION SELECTION
# ==============================================================================
echo ""
divider
echo -e "  ${BOLD}Step 3 │ Action${NC}"
divider

if [[ -z "$ACTION_NAME" ]]; then
    echo ""
    if [[ "$CURRENT_ROLE" != "none" ]]; then
        echo "  What do you want to do with this ${BOLD}${ROLE_NAME}${NC} node?"
    else
        echo "  What do you want to do?"
    fi
    echo ""
    echo -e "    ${BOLD}1)${NC}  Install     ${DIM}Fresh provisioning of the node${NC}"
    echo -e "    ${BOLD}2)${NC}  Update      ${DIM}Push latest configuration / payload${NC}"
    echo -e "    ${BOLD}3)${NC}  Verify      ${DIM}Run health checks${NC}"
    echo -e "    ${BOLD}4)${NC}  Uninstall   ${DIM}Clean removal of the node role${NC}"
    echo -e "    ${BOLD}5)${NC}  Control     ${DIM}Start / Stop / Restart services${NC}"
    echo ""
    prompt "Select action (1-5): " ACTION_CHOICE
    case "$ACTION_CHOICE" in
        1) ACTION_NAME="install" ;;
        2) ACTION_NAME="update" ;;
        3) ACTION_NAME="verify" ;;
        4) ACTION_NAME="uninstall" ;;
        5) ACTION_NAME="control" ;;
        *) error "Invalid choice. Exiting." ;;
    esac
fi

# ==============================================================================
# STEP 4: SAFETY & CONFIRMATION
# ==============================================================================
if [[ "$ACTION_NAME" == "install" && "$CURRENT_ROLE" != "none" ]]; then
    echo ""
    divider
    echo -e "  ${BOLD}Step 4 │ Safety Check${NC}"
    divider
    echo ""
    warning "This target already has a ${BOLD}${CURRENT_ROLE}${NC} installation."
    warning "A fresh install may overwrite critical services."
    if [[ "$AUTO_YES" == "false" ]]; then
        prompt "Type 'overwrite' to confirm destructive reinstall: " CONFIRM_OVERWRITE
        if [[ "${CONFIRM_OVERWRITE:-}" != "overwrite" ]]; then
             error "Overwrite not confirmed. Aborting."
        fi
    else
        info "--yes flag detected. Bypassing overwrite confirmation."
    fi
fi

# Hardware Checks (only for fresh installs)
if [[ "$ACTION_NAME" == "install" ]]; then
    check_hardware "$ROLE_NAME" "$EXEC_MODE" "$SSH_TARGET"
fi

# --- Role-Specific Options ---
if [[ "$ROLE_NAME" == "core" && "$ACTION_NAME" == "install" ]]; then
    if [[ -z "$VNC_CHOICE" ]]; then
        echo ""
        prompt "Enable VNC GUI for the AI Workbench? (y/N): " VNC_CHOICE
    fi
fi

# ==============================================================================
# TOPOLOGY WRITING
# ==============================================================================
echo "# Generated by Universal Orchestrator v2.0" > "$TOPOLOGY_FILE"
echo "SERVER_NAME=${ROLE_NAME}-node" >> "$TOPOLOGY_FILE"
echo "ROLE=$ROLE_NAME" >> "$TOPOLOGY_FILE"

if [[ "$ROLE_NAME" == "core" ]]; then
    if [[ "${VNC_CHOICE:-}" =~ ^[Yy]$ ]]; then
        echo "ENABLE_VNC=true" >> "$TOPOLOGY_FILE"
    else
        echo "ENABLE_VNC=false" >> "$TOPOLOGY_FILE"
    fi
fi

# ==============================================================================
# DEPLOYMENT PHASE
# ==============================================================================
echo ""
divider
echo -e "  ${BOLD}Deploying${NC}  ${ROLE_NAME} → ${ACTION_NAME}"
divider
echo ""

if [[ "$EXEC_MODE" == "local" ]]; then
    info "Initiating Local Pipeline [${ACTION_NAME}] for ${ROLE_NAME}..."

    if [[ ! -d "$ROLE_DIR" ]]; then
        warning "Directory $ROLE_DIR not populated in repo. Skipping module execution."
    else
        TARGET_SCRIPT="${ROLE_DIR}/scripts/${ACTION_NAME}.sh"
        if [[ -f "$TARGET_SCRIPT" ]]; then
            bash "$TARGET_SCRIPT" "${COMPONENT_NAME:-all}"
        else
            error "Management script not found: ${TARGET_SCRIPT}"
        fi
    fi

    # Write State (Only on install)
    if [[ "$ACTION_NAME" == "install" ]]; then
        write_state "$EXEC_MODE" "$SSH_TARGET" "$ROLE_NAME"
    fi

elif [[ "$EXEC_MODE" == "remote" ]]; then
    info "Initiating Remote Pipeline [${ACTION_NAME}] to ${SSH_TARGET}..."

    # 1. Create a remote temp directory
    ssh -q "$SSH_TARGET" "mkdir -p /tmp/nexus-install"

    # 2. Transfer payload
    info "Transferring payload to target..."
    rsync -avz --exclude='.git' --exclude='node_modules' ./ "$SSH_TARGET:/tmp/nexus-install/" > /dev/null

    # 3. Transfer topology config
    scp "$TOPOLOGY_FILE" "${SSH_TARGET}:/tmp/nexus-install/" > /dev/null

    # 4. Execute remote script & generate state
    info "Executing remote [${ACTION_NAME}] payload..."
    TARGET_SCRIPT="${ROLE_DIR}/scripts/${ACTION_NAME}.sh"

    ssh -t "$SSH_TARGET" "cd /tmp/nexus-install || exit 1; bash \"$TARGET_SCRIPT\" \"${COMPONENT_NAME:-all}\""

    # Write state on install
    if [[ "$ACTION_NAME" == "install" ]]; then
        write_state "$EXEC_MODE" "$SSH_TARGET" "$ROLE_NAME"
    fi

    success "Remote [${ACTION_NAME}] complete."
fi

echo ""
divider
success "Nexus Labs Orchestration Complete! 🚀"
divider
echo ""
