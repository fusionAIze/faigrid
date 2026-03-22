#!/usr/bin/env bash
TOOL_NAME="openrouter"
TOOL_CATEGORY="routers"
TOOL_DESC="OpenRouter CLI integration"
TOOL_TYPE="pipx"

_bootstrap_pipx() {
    if ! command -v pipx >/dev/null 2>&1; then
        sudo apt-get install -y pipx 2>/dev/null \
            || sudo python3 -m pip install pipx --break-system-packages
        export PATH="$PATH:$HOME/.local/bin"
        pipx ensurepath 2>/dev/null || true
    fi
}

tool_install()   { _bootstrap_pipx && pipx install openrouter-cli; }
tool_update()    { _bootstrap_pipx && pipx upgrade openrouter-cli; }
tool_status() {
    local ver
    ver=$(pipx list --short 2>/dev/null | awk '/^openrouter-cli /{print $2}')
    if [[ -n "$ver" ]]; then echo "Installed (${ver})"; else echo "Not installed"; fi
}
tool_uninstall() { pipx uninstall openrouter-cli 2>/dev/null || true; }

tool_configure() {
    local current
    current=$(grid_read_env "OPENROUTER_API_KEY")
    printf "  OPENROUTER_API_KEY [%s]: " "$(grid_mask "$current")"
    read -r -s api_key; echo ""
    [[ -z "$api_key" && -n "$current" ]] && { info "Kept existing key."; return 0; }
    [[ -z "$api_key" ]] && { warn "No key provided. Skipping."; return 0; }
    grid_write_env "OPENROUTER_API_KEY" "$api_key"
    grid_ensure_sourced
    success "OPENROUTER_API_KEY saved to ~/.config/faigrid/grid.env"
}
