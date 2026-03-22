#!/usr/bin/env bash
TOOL_NAME="kilo"
TOOL_CATEGORY="clis"
TOOL_DESC="Kilo Code CLI Agent (OpenCode fork)"
TOOL_TYPE="npm"
FAIGATE_CLIENT="kilocode"

tool_install() {
    sudo npm install -g @kilocode/cli || echo "Please check npm configuration."
}
tool_update() {
    sudo npm update -g @kilocode/cli
}
tool_status() {
    if command -v kilo >/dev/null 2>&1; then
        local ver
        ver=$(kilo --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}
tool_uninstall() { sudo npm uninstall -g @kilocode/cli; }

tool_configure() {
    local current
    current=$(grid_read_env "ANTHROPIC_API_KEY")
    info "Kilo Code uses the Anthropic API by default."
    printf "  ANTHROPIC_API_KEY [%s]: " "$(grid_mask "$current")"
    read -r -s api_key; echo ""
    [[ -z "$api_key" && -n "$current" ]] && { info "Kept existing key."; return 0; }
    [[ -z "$api_key" ]] && { warn "No key provided. Skipping."; return 0; }
    grid_write_env "ANTHROPIC_API_KEY" "$api_key"
    grid_ensure_sourced
    success "ANTHROPIC_API_KEY saved to ~/.config/faigrid/grid.env"
}
