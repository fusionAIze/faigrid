#!/usr/bin/env bash
TOOL_NAME="claude-cli"
TOOL_CATEGORY="clis"
TOOL_DESC="Anthropic Claude CLI agent"
TOOL_TYPE="npm"
FAIGATE_CLIENT="claude"

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
    current=$(grid_read_env "ANTHROPIC_API_KEY")
    printf "  ANTHROPIC_API_KEY [%s]: " "$(grid_mask "$current")"
    read -r -s api_key; echo ""
    [[ -z "$api_key" && -n "$current" ]] && { info "Kept existing key."; }
    if [[ -n "$api_key" ]]; then
        grid_write_env "ANTHROPIC_API_KEY" "$api_key"
        grid_ensure_sourced
        success "ANTHROPIC_API_KEY saved to ~/.config/faigrid/grid.env"
    fi

    # ── fusionAIze Gate integration ────────────────────────────────────────────
    local fg_port="${FAIGATE_PORT:-8090}"
    echo ""
    info "── fusionAIze Gate (Claude Code)"
    if curl -sf "http://127.0.0.1:${fg_port}/health" >/dev/null 2>&1; then
        info "  Gate is running at http://127.0.0.1:${fg_port}"
        info "  Claude Code routes through faigate via the hook system."
        info "  Hooks inject X-faigate-Mode and routing_hints per request."
        info "  No base-URL redirect needed — hooks handle it transparently."
        info "  Dashboard: http://127.0.0.1:${fg_port}/dashboard"
        echo ""
        info "  To verify hook integration:"
        info "    claude --version && curl -s http://127.0.0.1:${fg_port}/v1/stats | python3 -m json.tool"
    else
        warn "  fusionAIze Gate is not reachable at port ${fg_port}."
        info "  Start with: brew services start faigate  (or: faigate start)"
        info "  Claude Code hooks will activate automatically once the gate is running."
    fi
}
