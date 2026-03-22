#!/usr/bin/env bash
TOOL_NAME="mem0"
TOOL_CATEGORY="memory"
TOOL_DESC="Mem0 AI Memory Layer"
TOOL_TYPE="pipx"

_bootstrap_pipx() {
    if ! command -v pipx >/dev/null 2>&1; then
        sudo apt-get install -y pipx 2>/dev/null \
            || sudo python3 -m pip install pipx --break-system-packages
        export PATH="$PATH:$HOME/.local/bin"
        pipx ensurepath 2>/dev/null || true
    fi
}

tool_install()   { _bootstrap_pipx && pipx install mem0ai; }
tool_update()    { _bootstrap_pipx && pipx upgrade mem0ai; }
tool_status() {
    local ver
    ver=$(pipx list --short 2>/dev/null | awk '/^mem0ai /{print $2}')
    if [[ -n "$ver" ]]; then echo "Installed (${ver})"; else echo "Not installed"; fi
}
tool_uninstall() { pipx uninstall mem0ai 2>/dev/null || true; }

tool_configure() {
    local current
    current=$(nexus_read_env "MEM0_API_KEY")
    printf "  MEM0_API_KEY [%s]: " "$(nexus_mask "$current")"
    read -r -s api_key; echo ""
    [[ -z "$api_key" && -n "$current" ]] && { info "Kept existing key."; return 0; }
    [[ -z "$api_key" ]] && { warn "No key provided. Skipping."; return 0; }
    nexus_write_env "MEM0_API_KEY" "$api_key"
    nexus_ensure_sourced
    success "MEM0_API_KEY saved to ~/.config/nexus/nexus.env"
}
