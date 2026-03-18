#!/usr/bin/env bash
TOOL_NAME="claude-cli"
TOOL_CATEGORY="clis"
TOOL_DESC="Anthropic Claude CLI agent"
TOOL_TYPE="npm"

tool_install() {
    sudo npm install -g @anthropic-ai/claude-code || echo "Please check npm configuration."
}
tool_update() {
    sudo npm update -g @anthropic-ai/claude-code
}
tool_status() {
    if command -v claude >/dev/null 2>&1; then
        local ver
        ver=$(claude --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}
tool_uninstall() { sudo npm uninstall -g @anthropic-ai/claude-code; }

tool_configure() {
    local current
    current=$(nexus_read_env "ANTHROPIC_API_KEY")
    printf "  ANTHROPIC_API_KEY [%s]: " "$(nexus_mask "$current")"
    read -r -s api_key; echo ""
    [[ -z "$api_key" && -n "$current" ]] && { info "Kept existing key."; return 0; }
    [[ -z "$api_key" ]] && { warn "No key provided. Skipping."; return 0; }
    nexus_write_env "ANTHROPIC_API_KEY" "$api_key"
    nexus_ensure_sourced
    success "ANTHROPIC_API_KEY saved to ~/.config/nexus/nexus.env"
}
