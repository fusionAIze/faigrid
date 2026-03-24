#!/usr/bin/env bash
TOOL_NAME="deepseek"
TOOL_CATEGORY="clis"
TOOL_DESC="Unofficial DeepSeek CLI"
TOOL_TYPE="pipx"
FAIGATE_CLIENT="deepseek-cli"

_bootstrap_pipx() {
    if ! command -v pipx >/dev/null 2>&1; then
        sudo apt-get install -y pipx 2>/dev/null \
            || sudo python3 -m pip install pipx --break-system-packages
        export PATH="$PATH:$HOME/.local/bin"
        pipx ensurepath 2>/dev/null || true
    fi
}

tool_install() {
    _bootstrap_pipx
    pipx install deepseek-cli
}
tool_update() {
    _bootstrap_pipx
    pipx upgrade deepseek-cli
}
tool_status() {
    if command -v deepseek >/dev/null 2>&1; then
        local ver
        ver=$(deepseek --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}
tool_uninstall() { pipx uninstall deepseek-cli 2>/dev/null || true; }

tool_configure() {
    local current
    current=$(grid_read_env "DEEPSEEK_API_KEY")
    printf "  DEEPSEEK_API_KEY [%s]: " "$(grid_mask "$current")"
    read -r -s api_key; echo ""
    [[ -z "$api_key" && -n "$current" ]] && { info "Kept existing key."; }
    if [[ -n "$api_key" ]]; then
        grid_write_env "DEEPSEEK_API_KEY" "$api_key"
        grid_ensure_sourced
        success "DEEPSEEK_API_KEY saved to ~/.config/faigrid/grid.env"
    fi

    # ── fusionAIze Gate routing ────────────────────────────────────────────────
    local fg_port="${FAIGATE_PORT:-8090}"
    local fg_url="http://127.0.0.1:${fg_port}/v1"
    echo ""
    info "── fusionAIze Gate Routing (DeepSeek CLI)"
    if ! curl -sf "http://127.0.0.1:${fg_port}/health" >/dev/null 2>&1; then
        warn "  fusionAIze Gate not reachable at port ${fg_port} — skipping."
        info "  Start with: brew services start faigate"
        return 0
    fi
    info "  Gate is running at ${fg_url}"

    local cur_base
    cur_base=$(grid_read_env "DEEPSEEK_API_BASE" 2>/dev/null || echo "")
    local routed="no"
    [[ "$cur_base" == "$fg_url" ]] && routed="yes"

    printf "  Route DeepSeek CLI through faigate? current=[%s] (y/N): " "$routed"
    read -r route_choice

    if [[ "${route_choice:-N}" =~ ^[Yy]$ ]]; then
        # deepseek-cli respects DEEPSEEK_API_BASE (OpenAI-compat base URL)
        grid_write_env "DEEPSEEK_API_BASE" "$fg_url"
        grid_ensure_sourced
        success "  DEEPSEEK_API_BASE → ${fg_url} (saved to grid.env)"
        info "  DeepSeek CLI will use faigate's 'deepseek-cli' client profile."
        info "  Fallback chain: deepseek-chat → anthropic-haiku → gemini-flash"
        echo ""
        info "  Tip: faigate routes to deepseek-chat by default."
        info "  Use DEEPSEEK_API_BASE with any OpenAI-compat deepseek client."
    elif [[ "$routed" == "yes" ]]; then
        printf "  Disable faigate routing for DeepSeek CLI? (y/N): "
        read -r disable_choice
        if [[ "${disable_choice:-N}" =~ ^[Yy]$ ]]; then
            local tmp genv
            genv="${HOME}/.config/faigrid/grid.env"
            tmp=$(mktemp)
            grep -v "^DEEPSEEK_API_BASE=" "$genv" > "$tmp" 2>/dev/null || true
            mv "$tmp" "$genv"
            success "  DEEPSEEK_API_BASE removed — DeepSeek CLI routes directly."
        fi
    fi
}
