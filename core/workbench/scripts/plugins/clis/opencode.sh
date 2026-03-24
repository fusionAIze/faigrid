#!/usr/bin/env bash
TOOL_NAME="opencode"
TOOL_CATEGORY="clis"
TOOL_DESC="AI coding agent — terminal IDE"
TOOL_TYPE="npm"
TOOL_UPDATE_TYPE="npm"
TOOL_UPDATE_PKG="opencode-ai"
FAIGATE_CLIENT="opencode"

_detect_pkg_manager() {
    if   command -v apt-get >/dev/null 2>&1; then echo "apt"
    elif command -v dnf     >/dev/null 2>&1; then echo "dnf"
    elif command -v brew    >/dev/null 2>&1; then echo "brew"
    else                                          echo "unknown"
    fi
}

tool_install() {
    local pm
    pm=$(_detect_pkg_manager)
    if [[ "$pm" == "brew" ]]; then
        brew install opencode
    else
        # Remove any legacy v0.1.x before installing
        sudo npm uninstall -g opencode 2>/dev/null || true
        sudo npm install -g opencode-ai@latest
    fi
}

tool_update() {
    local pm
    pm=$(_detect_pkg_manager)
    if [[ "$pm" == "brew" ]]; then
        brew upgrade opencode
    else
        sudo npm install -g opencode-ai@latest
    fi
}

tool_status() {
    if command -v opencode >/dev/null 2>&1; then
        local ver
        ver=$(opencode --version 2>/dev/null | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}

tool_uninstall() {
    local pm
    pm=$(_detect_pkg_manager)
    if [[ "$pm" == "brew" ]]; then
        brew uninstall opencode
    else
        sudo npm uninstall -g opencode-ai
    fi
}

tool_configure() {
    info "opencode stores config at ~/.config/opencode/"
    info "Run 'opencode' to launch the interactive setup on first use."
    echo ""
    if command -v faigate >/dev/null 2>&1 || \
       curl -sf "http://127.0.0.1:${FAIGATE_PORT:-8090}/health" >/dev/null 2>&1; then
        info "fusionAIze Gate detected — set OPENAI_BASE_URL in your shell:"
        printf "  ${C_DIM}export OPENAI_BASE_URL=http://127.0.0.1:${FAIGATE_PORT:-8090}/v1${C_RESET}\n"
        printf "  Route via faigate? [y/N]: "
        read -r choice
        if [[ "${choice:-N}" =~ ^[Yy]$ ]]; then
            grid_write_env "OPENAI_BASE_URL" "http://127.0.0.1:${FAIGATE_PORT:-8090}/v1"
            grid_write_env "FAIGATE_CLIENT"  "opencode"
            grid_ensure_sourced
            success "OPENAI_BASE_URL written to grid.env"
        fi
    fi
}
