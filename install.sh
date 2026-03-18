#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - Advanced Universal Orchestrator
# Version 2.1.0
# ==============================================================================

set -euo pipefail

# --- Colors & Styling ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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
echo -e "${DIM}  Sovereign AI Infrastructure — Advanced Universal Orchestrator v2.1${NC}"
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

_quit() {
    echo ""
    divider
    success "Nexus Labs Orchestration Complete! 🚀"
    divider
    echo ""
    exit 0
}

STATE_FILE="$HOME/.nexus-state"
TOPOLOGY_FILE=".env.topology"
LOCAL_REGISTRY=".nexus/state"
# Repository root for relative path resolution
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_ROLE="none"
CURRENT_VERSION="none"

# Ensure local registry exists
mkdir -p "$LOCAL_REGISTRY"

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

    if [ "$mode" = "local" ]; then
        if [ -f "$STATE_FILE" ]; then
            # shellcheck disable=SC1090
            source "$STATE_FILE" || true
            CURRENT_ROLE=${NEXUS_ROLE:-none}
            CURRENT_VERSION=${NEXUS_VERSION:-none}
        fi
    elif [ "$mode" = "remote" ]; then
        # Check remote state safely
        if ssh -q -o ConnectTimeout=3 "$ssh_target" "[ -f \"\$HOME/.nexus-state\" ]" 2>/dev/null; then
            local remote_state
            remote_state=$(ssh -q -o ConnectTimeout=3 "$ssh_target" "cat \"\$HOME/.nexus-state\"" || echo "")
            if [ -n "$remote_state" ]; then
                CURRENT_ROLE=$(echo "$remote_state" | grep "NEXUS_ROLE" | cut -d'=' -f2 || echo "none")
                CURRENT_VERSION=$(echo "$remote_state" | grep "NEXUS_VERSION" | cut -d'=' -f2 || echo "none")
            fi
        fi
    fi
}

# --- Write State ---
write_state() {
    local mode=$1
    local ssh_target=$2
    local role=$3

    # Save to local registry first
    mkdir -p "$LOCAL_REGISTRY"
    {
        echo "NEXUS_ROLE=$role"
        echo "NEXUS_VERSION=latest"
        echo "INSTALL_DATE=$(date)"
        echo "EXEC_MODE=$mode"
        if [ "$mode" = "remote" ]; then
            echo "SSH_TARGET=$ssh_target"
        fi
    } > "$LOCAL_REGISTRY/${role}.state"

    if [ "$mode" = "local" ]; then
        {
            echo "NEXUS_ROLE=$role"
            echo "NEXUS_VERSION=latest"
            echo "INSTALL_DATE=$(date)"
        } > "$STATE_FILE"
        success "Saved state to ${STATE_FILE} (and local registry)"
    else
        ssh -q "$ssh_target" "echo 'NEXUS_ROLE=$role' > \"\$HOME/.nexus-state\"; \
            echo 'NEXUS_VERSION=latest' >> \"\$HOME/.nexus-state\"; \
            echo 'INSTALL_DATE=$(date)' >> \"\$HOME/.nexus-state\"" || true
        success "Saved remote state to ~/${ssh_target}:~/.nexus-state (and local registry)"
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

# --- Grid Status Probe ---
# Uses individual variables (Bash 3.2 compatible — no associative arrays)
GRID_STATUS_core="○"
GRID_STATUS_edge="○"
GRID_STATUS_worker="○"
GRID_STATUS_backup="○"
GRID_STATUS_external="○"

probe_grid_status() {
    # Check local registry only (instant)
    local roles=("core" "edge" "worker" "backup" "external")
    for role in "${roles[@]}"; do
        if [[ -f "$LOCAL_REGISTRY/${role}.state" ]]; then
            eval "GRID_STATUS_${role}=\"✔\""
        fi
    done
}

# --- Load Local State ---
# Retrieves target info (EXEC_MODE, SSH_TARGET) from registry
load_local_state() {
    local role=$1
    local state_file="$LOCAL_REGISTRY/${role}.state"
    if [ -f "$state_file" ]; then
        # Safer parsing for Bash 3.2 + set -e + pipefail
        while IFS='=' read -r key val; do
            if [ -z "$key" ] || echo "$key" | grep -q "^#"; then
                continue
            fi
            case "$key" in
                EXEC_MODE)  EXEC_MODE="$val" ;;
                SSH_TARGET) SSH_TARGET="$val" ;;
            esac
        done < "$state_file"

        if [ -n "${EXEC_MODE:-}" ]; then
            MODE_CHOICE="$EXEC_MODE"
        fi
    fi
    return 0
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

# Start of interactive wizard
set +e

# Probe known nodes from .nexus/state for registered icons
probe_grid_status

_grid_icon() {
    local role=$1
    local status
    case "$role" in
        core)     status="$GRID_STATUS_core" ;;
        edge)     status="$GRID_STATUS_edge" ;;
        worker)   status="$GRID_STATUS_worker" ;;
        backup)   status="$GRID_STATUS_backup" ;;
        external) status="$GRID_STATUS_external" ;;
        *)        status="○" ;;
    esac
    if [[ "$status" == "✔" ]]; then
        echo -e "${GREEN}✔${NC}"
    else
        echo -e "${DIM}○${NC}"
    fi
}

echo -e "    $(_grid_icon core)  ${BOLD}nexus-core${NC}       ${DIM}AI Workbench — n8n, OpenClaw, Postgres, Redis${NC}    ${YELLOW}[required]${NC}"
echo -e "    $(_grid_icon edge)  ${BOLD}nexus-edge${NC}       ${DIM}TLS ingress, reverse proxy, firewall, DNS${NC}      ${DIM}[optional]${NC}"
echo -e "    $(_grid_icon worker)  ${BOLD}nexus-worker${NC}     ${DIM}Local LLM inference — Ollama, LM Studio${NC}        ${DIM}[optional]${NC}"
echo -e "    $(_grid_icon backup)  ${BOLD}nexus-backup${NC}     ${DIM}Offsite storage vault — Synology, S3, USB${NC}      ${DIM}[optional]${NC}"
echo -e "    $(_grid_icon external)  ${BOLD}nexus-external${NC}   ${DIM}Cloud extension — ext. n8n, Plane PM${NC}           ${DIM}[optional]${NC}"
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
    echo -e "    ${BOLD}q)${NC}  Quit"
    echo ""
    prompt "Enter role (1-5 / q): " ROLE_CHOICE

    case "$ROLE_CHOICE" in
        1) ROLE_NAME="core" ;;
        2) ROLE_NAME="edge" ;;
        3) ROLE_NAME="worker" ;;
        4) ROLE_NAME="backup" ;;
        5) ROLE_NAME="external" ;;
        [Qq]|"") _quit ;;
        *) warning "Invalid choice. Please enter 1-5 or q." ;;
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

# Check for cached target info
load_local_state "$ROLE_NAME"

# ==============================================================================
# STEP 3: DEPLOY MODE
# ==============================================================================
echo ""
divider
echo -e "  ${BOLD}Step 3 │ Deploy Mode${NC}"
divider

if [[ -z "$MODE_CHOICE" ]]; then
    if [[ -n "${EXEC_MODE:-}" ]]; then
        # Known target found in registry
        local target_desc="Local Node"
        if [ "$EXEC_MODE" = "remote" ]; then
            target_desc="SSH: ${SSH_TARGET:-unknown}"
        fi
        
        echo ""
        echo -e "  ${CYAN}💡${NC}  Known target found for ${BOLD}${ROLE_NAME}${NC}:"
        echo ""
        echo -e "    ${BOLD}1)${NC}  Use existing  ${DIM}(${target_desc})${NC}"
        echo -e "    ${BOLD}2)${NC}  Change target ${DIM}(Switch to local/remote/new IP)${NC}"
        echo ""
        prompt "Choice (1/2): " USE_EXISTING
        if [ "$USE_EXISTING" = "2" ]; then
            EXEC_MODE=""
            MODE_CHOICE=""
            SSH_TARGET=""
        fi
    fi
fi

# If no cached mode (or user chose to change), ask
if [[ -z "$MODE_CHOICE" ]]; then
    echo ""
    echo -e "  How are you deploying ${BOLD}${ROLE_NAME}${NC}?"
    echo ""
    echo -e "    ${BOLD}1)${NC}  On-Node      ${DIM}— I am logged into the target node right now${NC}"
    echo -e "    ${BOLD}2)${NC}  Remote Push   ${DIM}— Push to a remote node via SSH from this workstation${NC}"
    echo ""
    prompt "Select mode (1/2): " MODE_CHOICE
    
    if [[ "$MODE_CHOICE" == "1" ]]; then
        EXEC_MODE="local"
    elif [[ "$MODE_CHOICE" == "2" ]]; then
        EXEC_MODE="remote"
    fi
fi

if [[ "$EXEC_MODE" == "remote" ]]; then
    if [[ -z "$SSH_TARGET" ]]; then
        default_ip="192.168.178.10"
        case "$ROLE_NAME" in
            core)   default_ip="192.168.178.20" ;;
            worker) default_ip="192.168.178.30" ;;
            backup) default_ip="192.168.178.40" ;;
        esac
        echo ""
        prompt "SSH target (e.g. nexus@${default_ip}): " SSH_TARGET
    fi

    info "Testing SSH connectivity to ${SSH_TARGET}..."
    if ! ssh -q "$SSH_TARGET" exit; then
        error "SSH connectivity to ${SSH_TARGET} failed. Ensure keys or passwords are correct."
    fi
    
    # Pre-flight: Check for rsync on remote target
    if ! ssh -q "$SSH_TARGET" "command -v rsync" > /dev/null; then
        warning "rsync is missing on ${SSH_TARGET}."
        prompt "Would you like to try installing rsync automatically via sudo? (y/n): " INSTALL_RSYNC
        if [[ "$INSTALL_RSYNC" == "y" ]]; then
            info "Attempting to install rsync on ${SSH_TARGET} (may prompt for password)..."
            # Use ssh -t to allow interactive sudo password prompt
            ssh -t "$SSH_TARGET" "sudo apt-get update && sudo apt-get install -y rsync"
            
            if ssh -q "$SSH_TARGET" "command -v rsync" > /dev/null; then
                success "rsync installed successfully."
            else
                error "rsync installation failed. Please install it manually (e.g., 'sudo apt install rsync') and try again."
            fi
        else
            error "rsync is required for remote deployment. Please install it manually and try again."
        fi
    fi
    success "Connected to ${SSH_TARGET} (rsync verified)."
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
        if [[ "$ROLE_NAME" == "core" ]]; then
            echo -e "    ${BOLD}6)${NC}  ${CYAN}Backup${NC}      ${DIM}Dump Postgres + n8n volume to /var/backups/nexus-core-heart${NC}"
        fi
        echo ""
        echo -e "    ${BOLD}h)${NC}  ${BOLD}Help / Connect${NC} ${DIM}How to access services from your workstation${NC}"
        echo -e "    ${BOLD}s)${NC}  Switch node    ${DIM}Go back to node selection (Step 2)${NC}"
        echo -e "    ${BOLD}q)${NC}  Quit"
        echo ""
        echo -e "  ${DIM}Tip: Start with Verify to see the current state of this node.${NC}"
        echo ""
        if [[ "$ROLE_NAME" == "core" ]]; then
            prompt "Select action (1-6 / h / s / q): " ACTION_CHOICE
        else
            prompt "Select action (1-5 / h / s / q): " ACTION_CHOICE
        fi
        case "$ACTION_CHOICE" in
            1) ACTION_NAME="verify" ;;
            2) ACTION_NAME="update" ;;
            3) ACTION_NAME="control" ;;
            4) ACTION_NAME="install" ;;
            5) ACTION_NAME="uninstall" ;;
            6) if [[ "$ROLE_NAME" == "core" ]]; then ACTION_NAME="backup"; else warning "Invalid choice."; fi ;;
            [Hh]) _show_help "$EXEC_MODE" "$SSH_TARGET" "$ROLE_NAME" ; exec bash "$0" ;;
            [Ss]) exec bash "$0" ;;
            [Qq]|"") _quit ;;
            *) warning "Invalid choice. Please enter 1-5, h, s, or q." ;;
        esac
    else
        # Fresh target — install is the natural first action
        echo -e "    ${BOLD}1)${NC}  Install     ${DIM}Set up this node with the ${ROLE_NAME} role${NC}"
        echo -e "    ${BOLD}2)${NC}  Verify      ${DIM}Check connectivity and environment (read-only)${NC}"
        echo ""
        echo -e "    ${BOLD}s)${NC}  Switch node  ${DIM}Go back to node selection (Step 2)${NC}"
        echo -e "    ${BOLD}q)${NC}  Quit"
        echo ""
        echo -e "  ${DIM}Tip: Start with Verify to check connectivity first.${NC}"
        echo ""
        prompt "Select action (1-2 / s / q): " ACTION_CHOICE
        case "$ACTION_CHOICE" in
            1) ACTION_NAME="install" ;;
            2) ACTION_NAME="verify" ;;
            [Ss]) exec bash "$0" ;;
            [Qq]|"") _quit ;;
            *) warning "Invalid choice. Please enter 1-2, s, or q." ;;
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

# Uninstall safety gate — warn before any data is touched
if [[ "$ACTION_NAME" == "uninstall" ]]; then
    echo ""
    divider
    echo -e "  ${BOLD}Step 5 │ Uninstall Safety Check${NC}"
    divider
    echo ""
    warning "You are about to UNINSTALL the ${BOLD}${ROLE_NAME}${NC} node."
    if [[ "$ROLE_NAME" == "core" ]]; then
        echo ""
        echo -e "  ${RED}✖${NC}  ${BOLD}ALL Docker volumes will be permanently deleted:${NC}"
        echo -e "     ${DIM}postgres_data${NC}  — n8n workflows, credentials, execution history"
        echo -e "     ${DIM}n8n_data${NC}       — n8n settings, installed nodes, encryption key"
        echo -e "     ${DIM}redis_data${NC}     — queue state"
        echo ""
        echo -e "  ${YELLOW}Tip: Run${NC} ${BOLD}Backup${NC} ${YELLOW}first to preserve your data.${NC}"
    fi
    echo ""
    if [[ "$AUTO_YES" == "false" ]]; then
        prompt "Type 'delete-all-data' to confirm permanent data loss: " CONFIRM_UNINSTALL
        if [[ "${CONFIRM_UNINSTALL:-}" != "delete-all-data" ]]; then
            error "Uninstall not confirmed. Aborting."
            exit 1
        fi
    else
        info "--yes flag detected. Bypassing uninstall confirmation."
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
# DEPLOYMENT PHASE — with post-action loop
# ==============================================================================

_run_action() {
    local mode=$1
    local ssh_target=$2
    local role=$3
    local action=$4
    local role_dir=$5
    
    local cmd_arg="${COMPONENT_NAME:-all}"

    # Handle control sub-commands interactively
    if [ "$action" = "control" ]; then
        echo ""
        echo -e "  ${BOLD}Control Interface${NC} — Select command for ${BOLD}${role}${NC}:"
        echo ""
        echo -e "    ${BOLD}1)${NC}  ${GREEN}Start${NC}"
        echo -e "    ${BOLD}2)${NC}  ${RED}Stop${NC}"
        echo -e "    ${BOLD}3)${NC}  ${YELLOW}Restart${NC}"
        echo -e "    ${BOLD}4)${NC}  Status"
        echo -e "    ${BOLD}5)${NC}  Reload"
        if [[ "$role" == "core" ]]; then
            echo -e "    ${BOLD}w)${NC}  ${MAGENTA}Workbench${NC}   ${DIM}AI Tooling (RTK, CLIs, Agents)${NC}"
        fi
        echo ""
        echo -e "    ${BOLD}a)${NC}  Action selection  ${DIM}(Back to Step 4)${NC}"
        echo ""
        prompt "Select command (1-5 / w / a / s / q): " CONTROL_CHOICE
        case "$CONTROL_CHOICE" in
            1) cmd_arg="start" ;;
            2) cmd_arg="stop" ;;
            3) cmd_arg="restart" ;;
            4) cmd_arg="status" ;;
            5) cmd_arg="reload" ;;
            [Ww]) if [[ "$role" == "core" ]]; then cmd_arg="workbench"; else warning "Workbench only available on core."; return 0; fi ;;
            [Aa]) return 0 ;;
            [Ss]) exec bash "$0" ;;
            [Qq]|"") _quit ;;
            *) warning "Invalid choice. Defaulting to 'status'." ; cmd_arg="status" ;;
        esac
    fi

    echo ""
    divider
    echo -e "  ${BOLD}Deploying${NC}  ${role} → ${action} (${cmd_arg})"
    divider
    echo ""

    if [ "$mode" = "local" ]; then
        info "Initiating Local Pipeline [${action}] for ${role}..."

        if [ ! -d "$role_dir" ]; then
            warning "Directory $role_dir not populated in repo. Skipping module execution."
        else
            TARGET_SCRIPT="${role_dir}/scripts/${action}.sh"
            if [ -f "$TARGET_SCRIPT" ]; then
                echo ""
                bash "$TARGET_SCRIPT" "$cmd_arg"
            else
                warning "Script not found: ${TARGET_SCRIPT}. Action skipped."
            fi
        fi

        if [ "$action" = "install" ]; then
            write_state "$mode" "$ssh_target" "$role"
        fi

    elif [ "$mode" = "remote" ]; then
        info "Initiating Remote Pipeline [${action}] to ${ssh_target}..."
        ssh -q "$ssh_target" "mkdir -p /tmp/nexus-install"
        info "Transferring payload to target..."
        rsync -az --exclude='.git' --exclude='node_modules' ./ "$ssh_target:/tmp/nexus-install/" > /dev/null
        scp "$TOPOLOGY_FILE" "${ssh_target}:/tmp/nexus-install/" > /dev/null
        info "Executing remote [${action}] payload..."
        echo ""
        
        # Calculate relative path from REPO_ROOT to target script
        REL_ROLE_DIR="${role_dir#$REPO_ROOT/}"
        TARGET_SCRIPT="${REL_ROLE_DIR}/scripts/${action}.sh"
        
        ssh -t "$ssh_target" "cd /tmp/nexus-install || exit 1; bash \"$TARGET_SCRIPT\" \"$cmd_arg\""
        if [ "$action" = "install" ]; then
            write_state "$mode" "$ssh_target" "$role"
        fi
    fi
}

# Show tailored connection help based on role and target
_show_help() {
    local mode=$1
    local ssh_target=$2
    local role=$3
    
    local ip="localhost"
    if [[ "$mode" == "remote" ]]; then
        # Extract IP from user@ip
        [[ "$ssh_target" == *"@"* ]] && ip=$(echo "$ssh_target" | cut -d'@' -f2) || ip="$ssh_target"
    fi

    echo ""
    divider
    echo -e "  ${BOLD}Access & Connection Guide │ ${role}${NC}"
    divider
    echo ""

    case "$role" in
        core)
            echo -e "  ${BOLD}n8n Automation Workbench:${NC}"
            echo -e "    Local URL  : http://${ip}:5678"
            if [[ "$mode" == "remote" ]]; then
                echo -e "    SSH Tunnel : ${CYAN}ssh -L 5678:localhost:5678 ${ssh_target}${NC}"
                echo -e "    ${DIM}(Run this on your workstation to access n8n in your local browser)${NC}"
            fi
            echo ""
            echo -e "  ${BOLD}OpenClaw Gateway:${NC}"
            echo -e "    Port       : 18789 (Internal)"
            echo -e "    Status     : Check via 'Verify' or 'Control'"
            ;;
        edge)
            echo -e "  ${BOLD}Pi-hole Admin:${NC}"
            echo -e "    URL        : http://${ip}/admin"
            echo ""
            echo -e "  ${BOLD}Caddy Ingress:${NC}"
            echo -e "    Ports      : 80 / 443"
            echo -e "    Config     : /etc/caddy/Caddyfile"
            ;;
        worker)
            echo -e "  ${BOLD}Ollama API:${NC}"
            echo -e "    Local URL  : http://${ip}:11434"
            if [[ "$mode" == "remote" ]]; then
                echo -e "    SSH Tunnel : ${CYAN}ssh -L 11434:localhost:11434 ${ssh_target}${NC}"
            fi
            ;;
        *)
            echo -e "  No specific connection help for this role yet."
            ;;
    esac

    echo ""
    echo -e "  ${BOLD}Documentation:${NC}"
    echo -e "    Runbooks   : docs/runbooks/"
    echo -e "    Architecture: docs/architecture.md"
    echo ""
    divider
}

# Destructive actions exit immediately; safe actions loop back
_is_loopable() {
    [[ "$1" == "verify" || "$1" == "update" || "$1" == "control" || "$1" == "backup" ]]
}

# Execute the requested action
_run_action "$EXEC_MODE" "$SSH_TARGET" "$ROLE_NAME" "$ACTION_NAME" "$ROLE_DIR"

if _is_loopable "$ACTION_NAME"; then
    while true; do
        echo ""
        divider
        inspect_state "$EXEC_MODE" "$SSH_TARGET"
        if [[ "$CURRENT_ROLE" != "none" ]]; then
            echo -e "  ${GREEN}✔${NC}  ${BOLD}${ROLE_NAME}${NC} is registered  ${DIM}(version: ${CURRENT_VERSION})${NC}"
        else
            echo -e "  ${DIM}○${NC}  ${BOLD}${ROLE_NAME}${NC} is ${YELLOW}not registered${NC} — run Install or Adopt to register"
        fi
        divider
        echo ""
        echo -e "  ${BOLD}What next?${NC}"
        echo ""
        echo -e "    ${BOLD}1)${NC}  ${GREEN}Verify${NC}      ${DIM}Read-only: check services, ports, disk${NC}"
        echo -e "    ${BOLD}2)${NC}  Update      ${DIM}System packages only (apt upgrade). Configs stay untouched${NC}"
        echo -e "    ${BOLD}3)${NC}  Control     ${DIM}Start / Stop / Restart managed services${NC}"
        echo ""
        echo -e "    ${BOLD}4)${NC}  ${YELLOW}Reinstall${NC}   ${DIM}⚠ Wipe and re-provision from scratch${NC}"
        echo -e "    ${BOLD}5)${NC}  ${YELLOW}Uninstall${NC}   ${DIM}⚠ Remove this node role entirely${NC}"
        if [[ "$ROLE_NAME" == "core" ]]; then
            echo -e "    ${BOLD}6)${NC}  ${CYAN}Backup${NC}      ${DIM}Dump Postgres + n8n volume to /var/backups/nexus-core-heart${NC}"
        fi
        echo ""
        echo -e "    ${BOLD}h)${NC}  ${BOLD}Help / Connect${NC}"
        echo -e "    ${BOLD}s)${NC}  Switch node  ${DIM}Go back to node selection (Step 2)${NC}"
        echo -e "    ${BOLD}q)${NC}  Quit"
        echo ""
        if [[ "$ROLE_NAME" == "core" ]]; then
            prompt "Select action (1-6 / h / s / q): " NEXT_CHOICE
        else
            prompt "Select action (1-5 / h / s / q): " NEXT_CHOICE
        fi
        case "$NEXT_CHOICE" in
            1) _run_action "$EXEC_MODE" "$SSH_TARGET" "$ROLE_NAME" "verify" "$ROLE_DIR" || true ;;
            2) _run_action "$EXEC_MODE" "$SSH_TARGET" "$ROLE_NAME" "update" "$ROLE_DIR" || true ;;
            3) _run_action "$EXEC_MODE" "$SSH_TARGET" "$ROLE_NAME" "control" "$ROLE_DIR" || true ;;
            4)
                warning "This will wipe and re-provision ${BOLD}${ROLE_NAME}${NC}. Are you sure?"
                prompt "Type YES to confirm: " CONFIRM
                if [[ "$CONFIRM" == "YES" ]]; then
                    _run_action "$EXEC_MODE" "$SSH_TARGET" "$ROLE_NAME" "install" "$ROLE_DIR"
                    break
                else
                    info "Reinstall cancelled."
                fi
                ;;
            5)
                if [[ "$ROLE_NAME" == "core" ]]; then
                    echo ""
                    warning "DESTRUCTIVE: This will permanently delete ALL Docker volumes!"
                    echo -e "  ${RED}✖${NC}  ${DIM}postgres_data${NC}  — n8n workflows, credentials, execution history"
                    echo -e "  ${RED}✖${NC}  ${DIM}n8n_data${NC}       — settings, installed nodes, encryption key"
                    echo -e "  ${RED}✖${NC}  ${DIM}redis_data${NC}     — queue state"
                    echo ""
                    echo -e "  ${YELLOW}Tip: Run${NC} ${BOLD}Backup (6)${NC} ${YELLOW}first to preserve your data.${NC}"
                    echo ""
                    prompt "Type 'delete-all-data' to confirm permanent data loss: " CONFIRM
                    if [[ "$CONFIRM" == "delete-all-data" ]]; then
                        _run_action "$EXEC_MODE" "$SSH_TARGET" "$ROLE_NAME" "uninstall" "$ROLE_DIR"
                        break
                    else
                        info "Uninstall cancelled."
                    fi
                else
                    warning "This will remove the ${BOLD}${ROLE_NAME}${NC} role. Are you sure?"
                    prompt "Type YES to confirm: " CONFIRM
                    if [[ "$CONFIRM" == "YES" ]]; then
                        _run_action "$EXEC_MODE" "$SSH_TARGET" "$ROLE_NAME" "uninstall" "$ROLE_DIR"
                        break
                    else
                        info "Uninstall cancelled."
                    fi
                fi
                ;;
            6)
                if [[ "$ROLE_NAME" == "core" ]]; then
                    _run_action "$EXEC_MODE" "$SSH_TARGET" "$ROLE_NAME" "backup" "$ROLE_DIR" || true
                else
                    warning "Invalid choice. Please enter 1-5, h, s, or q."
                fi
                ;;
            [Hh]) _show_help "$EXEC_MODE" "$SSH_TARGET" "$ROLE_NAME" ;;
            [Ss]) exec bash "$0" ;;
            [Qq]|"")
                break
                ;;
            *) warning "Invalid choice." ;;
        esac
    done
fi

echo ""
divider
success "Nexus Labs Orchestration Complete! 🚀"
divider
echo ""
