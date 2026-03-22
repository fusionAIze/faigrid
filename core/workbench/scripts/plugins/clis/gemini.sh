#!/usr/bin/env bash
TOOL_NAME="gemini-cli"
TOOL_CATEGORY="clis"
TOOL_DESC="Google Gemini CLI interface"
TOOL_TYPE="pipx"

_bootstrap_pipx() {
    if ! command -v pipx >/dev/null 2>&1; then
        sudo apt-get install -y pipx 2>/dev/null \
            || sudo python3 -m pip install pipx --break-system-packages
        export PATH="$PATH:$HOME/.local/bin"
        pipx ensurepath 2>/dev/null || true
    fi
}

tool_install() { _bootstrap_pipx && pipx install gemini-cli; }
tool_update()  { _bootstrap_pipx && pipx upgrade gemini-cli; }
tool_status() {
    if command -v gemini-cli >/dev/null 2>&1; then
        local ver
        ver=$(gemini-cli --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}
tool_uninstall() { pipx uninstall gemini-cli 2>/dev/null || true; }

tool_configure() {
    local current
    current=$(grid_read_env "GEMINI_API_KEY")
    printf "  GEMINI_API_KEY [%s]: " "$(grid_mask "$current")"
    read -r -s api_key; echo ""
    [[ -z "$api_key" && -n "$current" ]] && { info "Kept existing key."; return 0; }
    [[ -z "$api_key" ]] && { warn "No key provided. Skipping."; return 0; }
    grid_write_env "GEMINI_API_KEY" "$api_key"
    grid_ensure_sourced
    success "GEMINI_API_KEY saved to ~/.config/faigrid/grid.env"
}
