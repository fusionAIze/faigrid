#!/usr/bin/env bash
TOOL_NAME="codex"
TOOL_CATEGORY="clis"
TOOL_DESC="OpenAI Codex CLI interface"
TOOL_TYPE="npm"
FAIGATE_CLIENT="codex"

tool_install() {
    sudo npm install -g @openai/codex || echo "Please check npm configuration."
}
tool_update() {
    sudo npm update -g @openai/codex
}
tool_status() {
    if command -v codex >/dev/null 2>&1; then
        local ver
        ver=$(codex --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}
tool_uninstall() { sudo npm uninstall -g @openai/codex; }

tool_configure() {
    local current
    current=$(nexus_read_env "OPENAI_API_KEY")
    printf "  OPENAI_API_KEY [%s]: " "$(nexus_mask "$current")"
    read -r -s api_key; echo ""
    [[ -z "$api_key" && -n "$current" ]] && { info "Kept existing key."; return 0; }
    [[ -z "$api_key" ]] && { warn "No key provided. Skipping."; return 0; }
    nexus_write_env "OPENAI_API_KEY" "$api_key"
    nexus_ensure_sourced
    success "OPENAI_API_KEY saved to ~/.config/nexus/nexus.env"
}
