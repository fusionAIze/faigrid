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
    [[ -z "$api_key" && -n "$current" ]] && { info "Kept existing key."; }
    if [[ -n "$api_key" ]]; then
        grid_write_env "ANTHROPIC_API_KEY" "$api_key"
        grid_ensure_sourced
        success "ANTHROPIC_API_KEY saved to ~/.config/faigrid/grid.env"
    fi

    # ── fusionAIze Gate routing ────────────────────────────────────────────────
    local fg_port="${FAIGATE_PORT:-8090}"
    local fg_url="http://127.0.0.1:${fg_port}/v1"
    echo ""
    info "── fusionAIze Gate Routing (Kilo)"
    if ! curl -sf "http://127.0.0.1:${fg_port}/health" >/dev/null 2>&1; then
        warn "  fusionAIze Gate not reachable at port ${fg_port} — skipping."
        info "  Start with: brew services start faigate"
        return 0
    fi
    info "  Gate is running at ${fg_url}"

    # Detect kilo config path (OpenCode fork uses ~/.config/opencode or ~/.config/kilo)
    local kilo_cfg=""
    for _p in \
        "${HOME}/.config/kilo/kilo.json" \
        "${HOME}/.config/kilocode/config.json" \
        "${HOME}/.config/opencode/opencode.json"; do
        [[ -f "$_p" ]] && kilo_cfg="$_p" && break
    done

    local cur_openai_base
    cur_openai_base=$(grid_read_env "OPENAI_BASE_URL" 2>/dev/null || echo "")
    local routed="no"
    [[ "$cur_openai_base" == "$fg_url" ]] && routed="yes"

    printf "  Route Kilo through faigate (OPENAI_BASE_URL)? current=[%s] (y/N): " "$routed"
    read -r route_choice

    if [[ "${route_choice:-N}" =~ ^[Yy]$ ]]; then
        grid_write_env "OPENAI_BASE_URL" "$fg_url"
        grid_write_env "OPENAI_API_KEY" "local"
        grid_ensure_sourced
        success "  OPENAI_BASE_URL → ${fg_url} (saved to grid.env)"
        info "  Kilo requests will be routed through faigate using the 'kilocode' profile."
        if [[ -n "$kilo_cfg" ]]; then
            info "  Tip: also add a faigate provider in ${kilo_cfg} for model selection."
        fi
    fi

    if [[ -n "$kilo_cfg" ]]; then
        echo ""
        printf "  Patch faigate provider into ${kilo_cfg}? (y/N): "
        read -r patch_cfg
        if [[ "${patch_cfg:-N}" =~ ^[Yy]$ ]]; then
            if python3 - <<PYEOF
import json, sys
path = "${kilo_cfg}"
try:
    with open(path) as f:
        cfg = json.load(f)
except Exception:
    cfg = {}

cfg.setdefault("models", {}).setdefault("providers", {})["faigate"] = {
    "baseUrl": "${fg_url}",
    "apiKey":  "local",
    "auth":    "api-key",
    "api":     "openai-completions",
    "models": [
        {"id": "auto",              "name": "faigate Auto-Router",         "contextWindow": 200000, "maxTokens": 8000},
        {"id": "deepseek-chat",     "name": "DeepSeek Chat (via faigate)", "contextWindow": 128000, "maxTokens": 8000},
        {"id": "anthropic-haiku",   "name": "Haiku 3.5 (via faigate)",    "contextWindow": 200000, "maxTokens": 8000},
        {"id": "anthropic-sonnet",  "name": "Sonnet 4.6 (via faigate)",   "contextWindow": 200000, "maxTokens": 8000},
        {"id": "gemini-flash",      "name": "Gemini Flash (via faigate)", "contextWindow": 1000000,"maxTokens": 8000},
        {"id": "gemini-pro",        "name": "Gemini Pro (via faigate)",   "contextWindow": 1000000,"maxTokens": 8000},
    ]
}

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print("OK")
PYEOF
            then
                success "  faigate provider written to ${kilo_cfg}"
            else
                warn "  Failed to patch ${kilo_cfg}"
            fi
        fi
    fi
}
