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
    current=$(grid_read_env "OPENAI_API_KEY")
    printf "  OPENAI_API_KEY [%s]: " "$(grid_mask "$current")"
    read -r -s api_key; echo ""
    [[ -z "$api_key" && -n "$current" ]] && { info "Kept existing key."; }
    if [[ -n "$api_key" ]]; then
        grid_write_env "OPENAI_API_KEY" "$api_key"
        grid_ensure_sourced
        success "OPENAI_API_KEY saved to ~/.config/faigrid/grid.env"
    fi

    # ── fusionAIze Gate routing ────────────────────────────────────────────────
    local fg_port="${FAIGATE_PORT:-8090}"
    local fg_url="http://127.0.0.1:${fg_port}/v1"
    echo ""
    info "── fusionAIze Gate Routing (Codex)"
    if ! curl -sf "http://127.0.0.1:${fg_port}/health" >/dev/null 2>&1; then
        warn "  fusionAIze Gate not reachable at port ${fg_port} — skipping."
        info "  Start with: brew services start faigate"
        return 0
    fi
    info "  Gate is running at ${fg_url}"

    local cur_base
    cur_base=$(grid_read_env "OPENAI_BASE_URL" 2>/dev/null || echo "")
    local routed="no"
    [[ "$cur_base" == "$fg_url" ]] && routed="yes"

    printf "  Route Codex through faigate? current=[%s] (y/N): " "$routed"
    read -r route_choice

    if [[ "${route_choice:-N}" =~ ^[Yy]$ ]]; then
        # Save the real OPENAI key as a fallback (used by faigate's openai-gpt4o provider)
        [[ -n "$api_key" ]] && grid_write_env "OPENAI_API_KEY" "$api_key"
        # Point codex at faigate; use "local" as the key (faigate ignores it)
        grid_write_env "OPENAI_BASE_URL" "$fg_url"
        grid_ensure_sourced
        success "  OPENAI_BASE_URL → ${fg_url} (saved to grid.env)"
        info "  Codex will use faigate's 'codex' client profile for routing."
        info "  Default model: faigate/auto  (resolved to best available provider)"
        echo ""
        info "  To use a specific lane via Codex:"
        info "    OPENAI_API_KEY=local codex --model deepseek-chat  # DeepSeek via faigate"
        info "    OPENAI_API_KEY=local codex --model auto           # faigate auto-router"
    elif [[ "$routed" == "yes" ]]; then
        printf "  Disable faigate routing for Codex and restore direct OPENAI? (y/N): "
        read -r disable_choice
        if [[ "${disable_choice:-N}" =~ ^[Yy]$ ]]; then
            # Remove OPENAI_BASE_URL by setting blank (grid_write_env handles it)
            local tmp
            tmp=$(mktemp)
            local genv="${HOME}/.config/faigrid/grid.env"
            grep -v "^OPENAI_BASE_URL=" "$genv" > "$tmp" 2>/dev/null || true
            mv "$tmp" "$genv"
            success "  OPENAI_BASE_URL removed — Codex routes directly to OpenAI."
        fi
    fi
}
