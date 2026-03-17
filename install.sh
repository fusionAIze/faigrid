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

# --- Service Discovery ---
DISCOVERED_SERVICES=()

discover_services() {
    local mode=$1
    local ssh_target=$2
    local run_cmd

    if [[ "$mode" == "local" ]]; then
        run_cmd="bash -c"
    else
        run_cmd="ssh -q $ssh_target"
    fi

    info "Scanning target for existing services..."
    echo ""

    # Service probe list: name, check command
    local -a probes=(
        "Caddy:command -v caddy || pgrep -x caddy"
        "Pi-hole:command -v pihole || [ -d /etc/pihole ]"
        "Docker:command -v docker"
        "Ollama:command -v ollama || pgrep -x ollama"
        "LM Studio:command -v lms"
        "n8n:docker ps --format '{{.Names}}' 2>/dev/null | grep -q n8n"
        "PostgreSQL:command -v psql || docker ps --format '{{.Names}}' 2>/dev/null | grep -q postgres"
        "Redis:command -v redis-cli || docker ps --format '{{.Names}}' 2>/dev/null | grep -q redis"
        "Restic:command -v restic"
        "Tailscale:command -v tailscale"
        "Nginx:command -v nginx || pgrep -x nginx"
    )

    for probe in "${probes[@]}"; do
        local svc_name="${probe%%:*}"
        local svc_cmd="${probe#*:}"
        if $run_cmd "$svc_cmd" &>/dev/null; then
            DISCOVERED_SERVICES+=("$svc_name")
            echo -e "    ${GREEN}●${NC}  ${svc_name} detected"
        fi
    done

    if [[ ${#DISCOVERED_SERVICES[@]} -eq 0 ]]; then
        echo -e "    ${DIM}No known services detected (bare system).${NC}"
    fi
    echo ""
}

# ==============================================================================
# STEP 1: GRID OVERVIEW
# ==============================================================================
divider
echo -e "  ${BOLD}Step 1 │ Your Nexus Grid${NC}"
divider
echo ""
echo -e "  The Nexus ${BOLD}4+1 Architecture${NC} consists of these roles:"
echo ""
echo -e "    ${GREEN}●${NC}  ${BOLD}nexus-core${NC}       ${DIM}AI Workbench — n8n, OpenClaw, Postgres, Redis${NC}    ${YELLOW}[required]${NC}"
echo -e "    ${DIM}○${NC}  ${BOLD}nexus-edge${NC}       ${DIM}TLS ingress, reverse proxy, firewall, DNS${NC}      ${DIM}[optional]${NC}"
echo -e "    ${DIM}○${NC}  ${BOLD}nexus-worker${NC}     ${DIM}Local LLM inference — Ollama, LM Studio${NC}        ${DIM}[optional]${NC}"
echo -e "    ${DIM}○${NC}  ${BOLD}nexus-backup${NC}     ${DIM}Offsite storage vault — Synology, S3, USB${NC}      ${DIM}[optional]${NC}"
echo -e "    ${DIM}○${NC}  ${BOLD}nexus-external${NC}   ${DIM}Cloud extension — ext. n8n, Plane PM${NC}           ${DIM}[optional]${NC}"
echo ""
echo -e "  ${DIM}Tip: Start with nexus-core. Add other nodes as your grid grows.${NC}"

# ==============================================================================
# STEP 2: WHICH NODE TO PROVISION NOW
# ==============================================================================
echo ""
divider
echo -e "  ${BOLD}Step 2 │ Select Node to Provision${NC}"
divider

if [[ -z "$ROLE_NAME" ]]; then
    echo ""
    echo "  Which node do you want to work on right now?"
    echo ""
    echo -e "    ${BOLD}1)${NC}  nexus-core       ${DIM}The brain — always provision this first${NC}"
    echo -e "    ${BOLD}2)${NC}  nexus-edge       ${DIM}Secure ingress gateway (Caddy, DNS)${NC}"
    echo -e "    ${BOLD}3)${NC}  nexus-worker     ${DIM}Local LLM execution (MacBook, GPU server)${NC}"
    echo -e "    ${BOLD}4)${NC}  nexus-backup     ${DIM}Restic vault (NAS, USB disk, S3 bucket)${NC}"
    echo -e "    ${BOLD}5)${NC}  nexus-external   ${DIM}Public cloud node (VPS, agency server)${NC}"
    echo ""
    prompt "Enter role (1-5): " ROLE_CHOICE

    case "$ROLE_CHOICE" in
        1) ROLE_NAME="core" ;;
        2) ROLE_NAME="edge" ;;
        3) ROLE_NAME="worker" ;;
        4) ROLE_NAME="backup" ;;
        5) ROLE_NAME="external" ;;
        *) error "Invalid choice. Exiting." ;;
    esac

    # Smart suggestion for backup co-location
    if [[ "$ROLE_NAME" == "backup" ]]; then
        echo ""
        echo -e "  ${CYAN}💡 Tip:${NC} You don't need a dedicated backup node."
        echo -e "     Restic can run directly on ${BOLD}nexus-core${NC} or ${BOLD}nexus-external${NC},"
        echo -e "     backing up to a Synology NAS, S3 bucket, or USB drive."
        echo ""
        prompt "Continue with a dedicated backup node anyway? (Y/n): " BACKUP_CONFIRM
        if [[ "${BACKUP_CONFIRM:-Y}" =~ ^[Nn]$ ]]; then
            info "Returning to node selection..."
            exec bash "$0"
        fi
    fi
fi

ROLE_DIR="$(resolve_role_dir "$ROLE_NAME")"
success "Selected: ${BOLD}${ROLE_NAME}${NC}"

# ==============================================================================
# STEP 3: DEPLOY MODE
# ==============================================================================
echo ""
divider
echo -e "  ${BOLD}Step 3 │ Deploy Mode${NC}"
divider

if [[ -z "$MODE_CHOICE" ]]; then
    echo ""
    echo -e "  How are you deploying ${BOLD}${ROLE_NAME}${NC}?"
    echo ""
    echo -e "    ${BOLD}1)${NC}  On-Node      ${DIM}— I am logged into the target node right now${NC}"
    echo -e "    ${BOLD}2)${NC}  Remote Push   ${DIM}— Push to a remote node via SSH from this workstation${NC}"
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
    info "No .nexus-state file found. Scanning target for existing services..."
    echo ""
    discover_services "$EXEC_MODE" "$SSH_TARGET"

    # If services were discovered, suggest bootstrapping
    if [[ ${#DISCOVERED_SERVICES[@]} -gt 0 ]]; then
        echo -e "  ${CYAN}💡${NC}  Services are already running, but this node is ${BOLD}not registered${NC}"
        echo -e "     with Nexus Labs. You can:"
        echo ""
        echo -e "    ${BOLD}a)${NC}  ${GREEN}Adopt${NC}     ${DIM}— Register this node as ${BOLD}${ROLE_NAME}${NC}${DIM} (keeps everything as-is)${NC}"
        echo -e "    ${BOLD}b)${NC}  Continue  ${DIM}— Proceed to action selection without registering${NC}"
        echo ""
        prompt "Adopt or continue? (a/b): " ADOPT_CHOICE
        if [[ "${ADOPT_CHOICE:-a}" =~ ^[Aa]$ ]]; then
            write_state "$EXEC_MODE" "$SSH_TARGET" "$ROLE_NAME"
            CURRENT_ROLE="$ROLE_NAME"
            echo ""
            success "Node adopted as ${BOLD}${ROLE_NAME}${NC}. Future runs will recognize this node."
        fi
    fi
fi

# ==============================================================================
# BOOTSTRAP MODE: Register an existing node without running install scripts
# ==============================================================================
if [[ "$BOOTSTRAP_MODE" == "true" ]]; then
    echo ""
    write_state "$EXEC_MODE" "$SSH_TARGET" "$ROLE_NAME"
    echo ""
    success "Node bootstrapped as [${BOLD}${ROLE_NAME}${NC}]. Future runs will detect this role automatically."
    exit 0
fi

# If the target already has a different role, warn
if [[ "$CURRENT_ROLE" != "none" && "$CURRENT_ROLE" != "$ROLE_NAME" ]]; then
    echo ""
    warning "This target is already registered as ${BOLD}${CURRENT_ROLE}${NC}, but you selected ${BOLD}${ROLE_NAME}${NC}."
    prompt "Change this node's role? (y/N): " CHANGE_ROLE
    if [[ ! "${CHANGE_ROLE:-N}" =~ ^[Yy]$ ]]; then
        ROLE_NAME="$CURRENT_ROLE"
        ROLE_DIR="$(resolve_role_dir "$ROLE_NAME")"
        info "Keeping existing role: ${ROLE_NAME}"
    fi
fi


# ==============================================================================
# STEP 4: ACTION SELECTION
# ==============================================================================
echo ""
divider
echo -e "  ${BOLD}Step 4 │ Action${NC}"
divider

if [[ -z "$ACTION_NAME" ]]; then
    echo ""
    echo -e "  What do you want to do with this ${BOLD}${ROLE_NAME}${NC} node?"
    echo ""

    if [[ "$CURRENT_ROLE" != "none" ]]; then
        # Existing registered node — safe actions first, destructive at bottom
        echo -e "    ${BOLD}1)${NC}  ${GREEN}Verify${NC}      ${DIM}Read-only: check services, ports, disk (changes nothing)${NC}"
        echo -e "    ${BOLD}2)${NC}  Update      ${DIM}System packages only (apt upgrade). Your configs stay untouched${NC}"
        echo -e "    ${BOLD}3)${NC}  Control     ${DIM}Start / Stop / Restart managed services${NC}"
        echo ""
        echo -e "    ${BOLD}4)${NC}  ${YELLOW}Reinstall${NC}   ${DIM}⚠ Wipe and re-provision from scratch${NC}"
        echo -e "    ${BOLD}5)${NC}  ${YELLOW}Uninstall${NC}   ${DIM}⚠ Remove this node role entirely${NC}"
        echo ""
        echo -e "  ${DIM}Tip: Start with Verify to see the current state of this node.${NC}"
        echo ""
        prompt "Select action (1-5): " ACTION_CHOICE
        case "$ACTION_CHOICE" in
            1) ACTION_NAME="verify" ;;
            2) ACTION_NAME="update" ;;
            3) ACTION_NAME="control" ;;
            4) ACTION_NAME="install" ;;
            5) ACTION_NAME="uninstall" ;;
            *) error "Invalid choice. Exiting." ;;
        esac
    else
        # Fresh target — install is the natural first action
        echo -e "    ${BOLD}1)${NC}  Install     ${DIM}Set up this node with the ${ROLE_NAME} role${NC}"
        echo -e "    ${BOLD}2)${NC}  Verify      ${DIM}Check connectivity and environment (read-only)${NC}"
        echo ""
        prompt "Select action (1/2): " ACTION_CHOICE
        case "$ACTION_CHOICE" in
            1) ACTION_NAME="install" ;;
            2) ACTION_NAME="verify" ;;
            *) error "Invalid choice. Exiting." ;;
        esac
    fi
fi

# ==============================================================================
# STEP 5: SAFETY & CONFIRMATION
# ==============================================================================
if [[ "$ACTION_NAME" == "install" && "$CURRENT_ROLE" != "none" ]]; then
    echo ""
    divider
    echo -e "  ${BOLD}Step 5 │ Safety Check${NC}"
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
