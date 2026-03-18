#!/usr/bin/env bash
TOOL_NAME="openclaw"
TOOL_CATEGORY="agents"
TOOL_DESC="Host-native OpenClaw orchestrator"
TOOL_TYPE="systemd"

# Resolve path to the native server scripts sitting next to us in the repo.
# Works whether the repo is at its normal location or rsync'd to /tmp/nexus-install/.
_OC_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_OC_SERVER_DIR="$(cd "${_OC_HERE}/../../../../openclaw/native/server" 2>/dev/null && pwd)" \
    || _OC_SERVER_DIR=""

# ── Lifecycle ──────────────────────────────────────────────────────────────────

tool_install() {
    echo "Please use docs/runbooks/06-openclaw-native.md to install OpenClaw."
}

tool_update() {
    local update_script="${_OC_SERVER_DIR}/update.sh"

    # Show current version
    local current_ver
    current_ver=$(openclaw --version 2>/dev/null \
        | head -1 | grep -oE '[0-9]{4}\.[0-9]+\.[0-9]+-[0-9]+' | head -1 \
        || echo "unknown")

    info "Current version: ${current_ver}"
    info "State  /var/lib/openclaw/  and config  /etc/openclaw/  are untouched by update."
    printf "  Target version [%s]: " "${current_ver}"
    read -r target_ver

    if [[ -z "$target_ver" ]]; then
        info "No version entered — keeping ${current_ver}."
        return 0
    fi

    if [[ ! -f "$update_script" ]]; then
        warn "update.sh not found at ${update_script}. Restarting service only."
        sudo systemctl restart openclaw.service
        return 0
    fi

    info "Updating openclaw → ${target_ver}…"
    sudo "${update_script}" --version "${target_ver}"
    success "openclaw updated to ${target_ver} and service restarted."
}

tool_status() {
    if systemctl is-active --quiet openclaw.service 2>/dev/null; then
        local ver
        ver=$(openclaw --version 2>/dev/null | head -1 || echo "")
        echo "Installed (Running${ver:+ v${ver}})"
    elif systemctl is-enabled --quiet openclaw.service 2>/dev/null; then
        echo "Installed (Stopped)"
    else
        echo "Not installed"
    fi
}

tool_uninstall() {
    echo "Use docs/runbooks/06-openclaw-native.md to uninstall OpenClaw safely." >&2
}

# ── Configuration ──────────────────────────────────────────────────────────────
# Called from the Workbench Configure menu (option 5).
# _lib.sh is sourced in the subshell before this plugin, so nexus_read_env,
# nexus_mask, info, success, warn, C_DIM, C_RESET are all available.

tool_configure() {
    local providers_env="/etc/openclaw/openclaw.providers.env"

    # Bootstrap the file with correct perms if it doesn't exist yet
    if [[ ! -f "$providers_env" ]]; then
        sudo install -d -m 0750 -o root -g openclaw /etc/openclaw 2>/dev/null || true
        sudo install -m 0640 -o root -g openclaw /dev/null "$providers_env"
        info "Created ${providers_env}"
    fi

    info "Configuring OpenClaw — ${providers_env}"
    printf "  ${C_DIM}Press Enter to keep current. Keys already in nexus.env are offered as default.${C_RESET}\n\n"

    # Write one key into providers.env (silent read).
    # If empty input and key not yet set, falls back to matching nexus.env value.
    _oc_key() {
        local key="$1"
        local current nexus_val val tmp

        current=$(sudo grep "^${key}=" "$providers_env" 2>/dev/null \
            | cut -d'=' -f2- | tr -d '"' || echo "")
        nexus_val=$(nexus_read_env "$key" 2>/dev/null || echo "")

        if [[ -n "$current" ]]; then
            printf "  %-28s [%s]: " "$key" "$(nexus_mask "$current")"
        elif [[ -n "$nexus_val" ]]; then
            printf "  %-28s [${C_DIM}from nexus.env${C_RESET}]: " "$key"
        else
            printf "  %-28s [${C_DIM}(not set)${C_RESET}]: " "$key"
        fi

        read -r -s val; echo ""

        if [[ -z "$val" ]]; then
            # Empty input: adopt nexus.env value if current is not set
            if [[ -z "$current" && -n "$nexus_val" ]]; then
                val="$nexus_val"
                info "  Using ${key} from nexus.env"
            else
                return 0  # keep existing
            fi
        fi

        tmp=$(mktemp)
        sudo grep -v "^${key}=" "$providers_env" > "$tmp" 2>/dev/null || true
        printf '%s=%s\n' "$key" "$val" >> "$tmp"
        sudo mv "$tmp" "$providers_env"
        sudo chown root:openclaw "$providers_env"
        sudo chmod 0640 "$providers_env"
    }

    info "── Providers"
    _oc_key "DEEPSEEK_API_KEY"
    _oc_key "ANTHROPIC_API_KEY"
    _oc_key "OPENAI_API_KEY"
    _oc_key "GEMINI_API_KEY"
    _oc_key "OPENROUTER_API_KEY"
    echo ""

    info "── Channel Bots"
    _oc_key "TELEGRAM_BOT_TOKEN"
    _oc_key "DISCORD_BOT_TOKEN"
    echo ""

    # ── FoundryGate provider (openclaw.json) ─────────────────────────────────
    info "── FoundryGate Provider (openclaw.json)"

    local oc_json="/var/lib/openclaw/.openclaw-prod/openclaw.json"

    # Show current foundrygate entry if present
    local cur_fg_url cur_fg_key cur_primary
    cur_fg_url=$(sudo python3 -c "
import json, sys
try:
    cfg = json.load(open('${oc_json}'))
    fg = cfg.get('models',{}).get('providers',{}).get('foundrygate',{})
    print(fg.get('baseUrl',''))
except: print('')
" 2>/dev/null || echo "")
    cur_fg_key=$(sudo python3 -c "
import json, sys
try:
    cfg = json.load(open('${oc_json}'))
    fg = cfg.get('models',{}).get('providers',{}).get('foundrygate',{})
    print(fg.get('apiKey',''))
except: print('')
" 2>/dev/null || echo "")
    cur_primary=$(sudo python3 -c "
import json, sys
try:
    cfg = json.load(open('${oc_json}'))
    print(cfg.get('agents',{}).get('defaults',{}).get('model',{}).get('primary',''))
except: print('')
" 2>/dev/null || echo "")

    if [[ -n "$cur_fg_url" ]]; then
        info "  Current: baseUrl=${cur_fg_url}  apiKey=${cur_fg_key}"
    else
        info "  foundrygate: not yet configured"
    fi

    # Auto-detect port from FoundryGate .env if installed
    local fg_port="8090"
    local fg_env="/opt/fusionaize-nexus/foundrygate/.env"
    if [[ -f "$fg_env" ]]; then
        local detected_port
        detected_port=$(grep "^FOUNDRYGATE_PORT=" "$fg_env" 2>/dev/null \
            | cut -d'=' -f2 | tr -d '"' || echo "")
        [[ -n "$detected_port" ]] && fg_port="$detected_port"
    fi

    printf "  FoundryGate port        [%s]: " "${cur_fg_url:-$fg_port}"
    read -r input_port
    [[ -n "$input_port" ]] && fg_port="$input_port" \
        || { [[ -n "$cur_fg_url" ]] && fg_port=$(echo "$cur_fg_url" \
             | grep -oE ':[0-9]+/' | tr -d ':/'); }

    printf "  FoundryGate apiKey      [%s]: " "${cur_fg_key:-local}"
    read -r fg_token
    [[ -z "$fg_token" ]] && fg_token="${cur_fg_key:-local}"

    printf "  Set foundrygate/auto as primary model? current=[%s] (y/N): " \
        "${cur_primary:-(not set)}"
    read -r set_primary
    local fg_set_default="no"
    [[ "${set_primary:-N}" =~ ^[Yy]$ ]] && fg_set_default="yes"

    # Patch openclaw.json via python3
    # Root can write to the openclaw:openclaw 600 file; inode stays → perms unchanged.
    local tmppy
    tmppy=$(mktemp)
    cat > "$tmppy" << PYEOF
import json

with open("${oc_json}") as f:
    cfg = json.load(f)

cfg.setdefault("models", {}).setdefault("providers", {})["foundrygate"] = {
    "baseUrl": "http://127.0.0.1:${fg_port}/v1",
    "apiKey": "${fg_token}",
    "auth": "api-key",
    "api": "openai-completions",
    "models": [
        {"id": "auto",              "name": "FoundryGate Auto-Router",             "contextWindow": 128000,  "maxTokens": 8000},
        {"id": "deepseek-chat",     "name": "DeepSeek Chat (via FoundryGate)",     "contextWindow": 128000,  "maxTokens": 8000},
        {"id": "deepseek-reasoner", "name": "DeepSeek Reasoner (via FoundryGate)", "contextWindow": 128000,  "maxTokens": 8000},
        {"id": "gemini-flash",      "name": "Gemini Flash (via FoundryGate)",      "contextWindow": 1000000, "maxTokens": 8000},
        {"id": "gemini-flash-lite", "name": "Gemini Flash-Lite (via FoundryGate)", "contextWindow": 1000000, "maxTokens": 8000},
    ]
}

if "${fg_set_default}" == "yes":
    cfg.setdefault("agents", {}).setdefault("defaults", {}).setdefault("model", {})["primary"] = "foundrygate/auto"

with open("${oc_json}", "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print("OK")
PYEOF

    if sudo python3 "$tmppy"; then
        success "foundrygate provider written to ${oc_json}"
    else
        warn "Failed to patch ${oc_json}"
    fi
    rm -f "$tmppy"
    echo ""

    # Model probe — runs as the openclaw system user to load providers.env correctly
    printf "  Run model probe (max 16 tokens)? (y/N): "
    read -r run_probe
    if [[ "${run_probe:-N}" =~ ^[Yy]$ ]]; then
        info "Probing models…"
        sudo -u openclaw -H bash -lc \
            "set -a; . ${providers_env}; set +a; \
             openclaw --profile prod models status --probe --probe-max-tokens 16" \
            2>&1 | sed -n '1,140p' \
            || warn "Probe had errors — check: sudo journalctl -u openclaw.service -n 50"
    fi
    echo ""

    # Restart to apply new provider keys
    printf "  Restart openclaw.service to apply? (y/N): "
    read -r do_restart
    if [[ "${do_restart:-N}" =~ ^[Yy]$ ]]; then
        sudo systemctl restart openclaw.service
        success "openclaw service restarted."
    fi

    success "OpenClaw configuration saved to ${providers_env}"
}
