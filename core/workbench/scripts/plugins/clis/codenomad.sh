#!/usr/bin/env bash
TOOL_NAME="codenomad"
TOOL_CATEGORY="clis"
TOOL_DESC="Browser-based remote dev server (CodeNomad)"
TOOL_TYPE="npm"
TOOL_UPDATE_TYPE="npm"
TOOL_UPDATE_PKG="@neuralnomads/codenomad"
TOOL_DEPS="opencode"

tool_install() {
    # Requires opencode in PATH
    if ! command -v opencode >/dev/null 2>&1; then
        warn "opencode not found — install opencode first (it is required by codenomad)."
        return 1
    fi
    sudo npm install -g @neuralnomads/codenomad
}

tool_update() {
    sudo npm install -g @neuralnomads/codenomad@latest
}

tool_status() {
    if command -v codenomad >/dev/null 2>&1 || \
       npm list -g --depth=0 @neuralnomads/codenomad >/dev/null 2>&1; then
        local ver
        ver=$(npm list -g --depth=0 @neuralnomads/codenomad 2>/dev/null \
            | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
        echo "Installed${ver:+ (v${ver})}"
    else
        echo "Not installed"
    fi
}

tool_uninstall() {
    sudo npm uninstall -g @neuralnomads/codenomad
}

tool_configure() {
    info "CodeNomad launches a local server accessible from the browser."
    info "Start with: codenomad --launch"
    echo ""
    info "Default port: 3000 — access at http://localhost:3000"
    info "Requires opencode CLI in PATH for AI features."
}
