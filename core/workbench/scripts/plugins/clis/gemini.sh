#!/usr/bin/env bash
TOOL_NAME="gemini-cli"
TOOL_CATEGORY="clis"
TOOL_DESC="Google Gemini CLI interface"
TOOL_TYPE="pipx"
FAIGATE_CLIENT="gemini-cli"

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
    [[ -z "$api_key" && -n "$current" ]] && { info "Kept existing key."; }
    if [[ -n "$api_key" ]]; then
        grid_write_env "GEMINI_API_KEY" "$api_key"
        grid_ensure_sourced
        success "GEMINI_API_KEY saved to ~/.config/faigrid/grid.env"
    fi

    # ── fusionAIze Gate routing ────────────────────────────────────────────────
    local fg_port="${FAIGATE_PORT:-8090}"
    local fg_url="http://127.0.0.1:${fg_port}/v1"
    echo ""
    info "── fusionAIze Gate Routing (Gemini CLI)"
    if ! curl -sf "http://127.0.0.1:${fg_port}/health" >/dev/null 2>&1; then
        warn "  fusionAIze Gate not reachable at port ${fg_port} — skipping."
        info "  Start with: brew services start faigate"
        return 0
    fi
    info "  Gate is running at ${fg_url}"
    info "  Gemini CLI uses Google's native protocol; direct faigate routing"
    info "  is available if gemini-cli supports OPENAI_BASE_URL override."
    echo ""

    local cur_base
    cur_base=$(grid_read_env "OPENAI_BASE_URL" 2>/dev/null || echo "")
    local routed="no"
    [[ "$cur_base" == "$fg_url" ]] && routed="yes"

    printf "  Route Gemini CLI through faigate via OPENAI_BASE_URL? current=[%s] (y/N): " "$routed"
    read -r route_choice

    if [[ "${route_choice:-N}" =~ ^[Yy]$ ]]; then
        grid_write_env "OPENAI_BASE_URL" "$fg_url"
        grid_write_env "OPENAI_API_KEY" "local"
        grid_ensure_sourced
        success "  OPENAI_BASE_URL → ${fg_url} (saved to grid.env)"
        info "  Note: faigate will route gemini-cli requests using the 'gemini-cli' profile."
        info "  Preferred providers: gemini-flash, gemini-flash-lite, gemini-pro"
    fi
    echo ""
    info "  Dashboard: http://127.0.0.1:${fg_port}/dashboard"
}
