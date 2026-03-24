#!/usr/bin/env bash
TOOL_NAME="deer-flow"
TOOL_CATEGORY="automation"
TOOL_DESC="ByteDance AI research & workflow orchestrator"
TOOL_TYPE="git"
TOOL_UPDATE_TYPE="github"
TOOL_UPDATE_REPO="bytedance/deer-flow"

INSTALL_DIR="/opt/faigrid/deer-flow"
DEERFLOW_PORT="${DEERFLOW_PORT:-2026}"

tool_install() {
    if [[ -d "$INSTALL_DIR" ]]; then
        warn "deer-flow already cloned at ${INSTALL_DIR}."
        return 0
    fi
    sudo git clone https://github.com/bytedance/deer-flow.git "$INSTALL_DIR"
    sudo chown -R "$(id -u):$(id -g)" "$INSTALL_DIR"
    info "Run 'make config' in ${INSTALL_DIR} to complete setup."
    info "Then start with: make up  (Docker)  or  make dev  (local Python)"
}

tool_update() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        warn "deer-flow not found at ${INSTALL_DIR}."
        return 1
    fi
    info "Pulling latest deer-flow…"
    ( cd "$INSTALL_DIR" && git pull )
    info "Re-run 'make config' if configuration schema changed."
    info "Restart with: make up  or  make dev"
}

tool_status() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        echo "Not installed"
        return
    fi
    local rev
    rev=$(git -C "$INSTALL_DIR" describe --tags --abbrev=0 2>/dev/null \
        || git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null \
        || echo "unknown")
    if curl -sf "http://127.0.0.1:${DEERFLOW_PORT}/" >/dev/null 2>&1; then
        echo "Installed (${rev}, running — http://127.0.0.1:${DEERFLOW_PORT})"
    else
        echo "Installed (${rev}, stopped)"
    fi
}

tool_uninstall() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        warn "deer-flow not found at ${INSTALL_DIR}."
        return 0
    fi
    # Stop Docker stack first if running
    if [[ -f "${INSTALL_DIR}/docker-compose.yml" ]] || \
       [[ -f "${INSTALL_DIR}/compose.yaml" ]]; then
        ( cd "$INSTALL_DIR" && docker compose down 2>/dev/null ) || true
    fi
    sudo rm -rf "$INSTALL_DIR"
    success "deer-flow removed."
}

tool_configure() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        warn "deer-flow not installed — run Install first."
        return 1
    fi

    info "deer-flow configuration — ${INSTALL_DIR}"
    echo ""
    printf "  ${C_BOLD}1)${C_RESET}  Run 'make config'   ${C_DIM}Interactive setup (LLM keys, search APIs)${C_RESET}\n"
    printf "  ${C_BOLD}2)${C_RESET}  Start (Docker)      ${C_DIM}make up — production mode${C_RESET}\n"
    printf "  ${C_BOLD}3)${C_RESET}  Start (local dev)   ${C_DIM}make dev — Python venv mode${C_RESET}\n"
    printf "  ${C_BOLD}4)${C_RESET}  Stop                ${C_DIM}make down (Docker only)${C_RESET}\n"
    echo ""
    read -r -p "  ▸ Choice (c = cancel): " cfg_choice
    case "$cfg_choice" in
        1) ( cd "$INSTALL_DIR" && make config ) ;;
        2) ( cd "$INSTALL_DIR" && make up ) ;;
        3) ( cd "$INSTALL_DIR" && make dev ) ;;
        4) ( cd "$INSTALL_DIR" && make down ) ;;
        c|C|"") info "Cancelled."; return ;;
        *) warn "Invalid choice." ;;
    esac
}
