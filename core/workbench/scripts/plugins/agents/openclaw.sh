#!/usr/bin/env bash
TOOL_NAME="openclaw"
TOOL_CATEGORY="agents"
TOOL_DESC="Host-native OpenClaw orchestrator"
TOOL_TYPE="systemd"
TOOL_UPDATE_TYPE="github"
TOOL_UPDATE_REPO="openclaw/openclaw"
TOOL_SERVICE="openclaw"

# Resolve path to the native server scripts sitting next to us in the repo.
# Works whether the repo is at its normal location or rsync'd to /tmp/grid-install/.
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
        | head -1 | grep -oE '[0-9]{4}\.[0-9]+\.[0-9]+(-[0-9]+)?' | head -1 \
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
# _lib.sh is sourced in the subshell before this plugin, so grid_read_env,
# grid_mask, info, success, warn, C_DIM, C_RESET are all available.

tool_configure() {
    local providers_env="/etc/openclaw/openclaw.providers.env"

    # Bootstrap the file with correct perms if it doesn't exist yet.
    # Use `sudo test -f` because /etc/openclaw/ is 750 root:openclaw — the
    # calling user can't traverse it, so a plain [[ -f ]] always returns false
    # and would silently overwrite an existing file.
    if ! sudo test -f "$providers_env" 2>/dev/null; then
        sudo install -d -m 0750 -o root -g openclaw /etc/openclaw 2>/dev/null || true
        sudo install -m 0640 -o root -g openclaw /dev/null "$providers_env"
        info "Created ${providers_env}"
    fi

    info "Configuring OpenClaw — ${providers_env}"
    printf "  ${C_DIM}Press Enter to keep current. Keys already in grid.env are offered as default.${C_RESET}\n\n"

    # Write one key into providers.env (silent read).
    # If empty input and key not yet set, falls back to matching grid.env value.
    _oc_key() {
        local key="$1"
        local current grid_val val tmp

        current=$(sudo grep "^${key}=" "$providers_env" 2>/dev/null \
            | cut -d'=' -f2- | tr -d '"' || echo "")
        grid_val=$(grid_read_env "$key" 2>/dev/null || echo "")

        if [[ -n "$current" ]]; then
            printf "  %-28s [%s]: " "$key" "$(grid_mask "$current")"
        elif [[ -n "$grid_val" ]]; then
            printf "  %-28s [${C_DIM}from grid.env${C_RESET}]: " "$key"
        else
            printf "  %-28s [${C_DIM}(not set)${C_RESET}]: " "$key"
        fi

        read -r -s val; echo ""

        if [[ -z "$val" ]]; then
            # Empty input: adopt grid.env value if current is not set
            if [[ -z "$current" && -n "$grid_val" ]]; then
                val="$grid_val"
                info "  Using ${key} from grid.env"
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

    # ── fusionAIze Gate provider (openclaw.json) ──────────────────────────────
    info "── fusionAIze Gate Provider (openclaw.json)"

    local oc_json="/var/lib/openclaw/.openclaw-prod/openclaw.json"

    # Read current state in one python3 pass
    local cur_state
    cur_state=$(sudo python3 -c "
import json, sys
try:
    cfg = json.load(open('${oc_json}'))
    providers = cfg.get('models',{}).get('providers',{})
    fg = providers.get('faigate', providers.get('foundrygate', {}))
    has_legacy = 'yes' if ('foundrygate' in providers or 'clawgate' in providers) else 'no'
    primary = cfg.get('agents',{}).get('defaults',{}).get('model',{}).get('primary','')
    print(fg.get('baseUrl','') + '|' + fg.get('apiKey','') + '|' + primary + '|' + has_legacy)
except Exception:
    print('|||no')
" 2>/dev/null || echo "|||no")

    local cur_fg_url cur_fg_key cur_primary has_legacy
    cur_fg_url=$(  echo "$cur_state" | cut -d'|' -f1)
    cur_fg_key=$(  echo "$cur_state" | cut -d'|' -f2)
    cur_primary=$( echo "$cur_state" | cut -d'|' -f3)
    has_legacy=$(  echo "$cur_state" | cut -d'|' -f4)

    if [[ -n "$cur_fg_url" ]]; then
        info "  Current: baseUrl=${cur_fg_url}  apiKey=${cur_fg_key}"
    else
        info "  faigate: not yet configured"
    fi

    # Auto-detect port from faigate .env if installed
    local fg_port="8090"
    for _fg_env in \
        "/opt/homebrew/etc/faigate/faigate.env" \
        "$(brew --prefix 2>/dev/null)/etc/faigate/faigate.env" \
        "/opt/faigrid/faigate/.env" \
        "/opt/faigrid/foundrygate/.env"; do
        # Use test without sudo for Homebrew paths (user-owned), sudo for system paths
        if [[ "$_fg_env" == /opt/homebrew/* ]] || [[ "$_fg_env" == /usr/local/* ]]; then
            [[ -f "$_fg_env" ]] || continue
            local detected_port
            detected_port=$(grep -E "^FAIGATE_PORT=|^FOUNDRYGATE_PORT=" "$_fg_env" 2>/dev/null \
                | head -1 | cut -d'=' -f2 | tr -d '"' || echo "")
        else
            sudo test -f "$_fg_env" 2>/dev/null || continue
            local detected_port
            detected_port=$(sudo grep -E "^FAIGATE_PORT=|^FOUNDRYGATE_PORT=" "$_fg_env" 2>/dev/null \
                | head -1 | cut -d'=' -f2 | tr -d '"' || echo "")
        fi
        [[ -n "$detected_port" ]] && fg_port="$detected_port"
        break
    done

    # Derive current port from existing URL for display
    local cur_port
    cur_port=$(echo "$cur_fg_url" | grep -oE ':[0-9]+' | tr -d ':' | head -1 || echo "")

    printf "  fusionAIze Gate port    [%s]: " "${cur_port:-$fg_port}"
    read -r input_port
    if [[ -n "$input_port" ]]; then
        fg_port="$input_port"
    elif [[ -n "$cur_port" ]]; then
        fg_port="$cur_port"
    fi

    printf "  apiKey                  [%s]: " "${cur_fg_key:-local}"
    read -r fg_token
    [[ -z "$fg_token" ]] && fg_token="${cur_fg_key:-local}"

    printf "  Set faigate/auto as primary? current=[%s] (y/N): " \
        "${cur_primary:-(not set)}"
    read -r set_primary
    local fg_set_default="no"
    [[ "${set_primary:-N}" =~ ^[Yy]$ ]] && fg_set_default="yes"

    # Offer to remove legacy foundrygate / clawgate entries if present
    local remove_legacy="no"
    if [[ "$has_legacy" == "yes" ]]; then
        printf "  Remove legacy 'foundrygate'/'clawgate' provider entries? (y/N): "
        read -r rm_lg
        [[ "${rm_lg:-N}" =~ ^[Yy]$ ]] && remove_legacy="yes"
    fi

    # Patch openclaw.json via python3.
    # Root writes to the openclaw:openclaw 600 file; inode is unchanged → perms stay.
    local tmppy
    tmppy=$(mktemp)
    cat > "$tmppy" << PYEOF
import json

with open("${oc_json}") as f:
    cfg = json.load(f)

# Write faigate provider block with all fusionAIze Gate model IDs
cfg.setdefault("models", {}).setdefault("providers", {})["faigate"] = {
    "baseUrl": "http://127.0.0.1:${fg_port}/v1",
    "apiKey":  "${fg_token}",
    "auth":    "api-key",
    "api":     "openai-completions",
    "models": [
        {"id": "auto",                "name": "faigate Auto-Router",              "contextWindow": 200000,  "maxTokens": 8000},
        {"id": "deepseek-chat",       "name": "DeepSeek Chat (via faigate)",      "contextWindow": 128000,  "maxTokens": 8000},
        {"id": "deepseek-reasoner",   "name": "DeepSeek Reasoner (via faigate)",  "contextWindow": 128000,  "maxTokens": 8000},
        {"id": "gemini-flash-lite",   "name": "Gemini Flash-Lite (via faigate)",  "contextWindow": 1000000, "maxTokens": 8000},
        {"id": "gemini-flash",        "name": "Gemini Flash (via faigate)",       "contextWindow": 1000000, "maxTokens": 8000},
        {"id": "local-worker",        "name": "Local Worker (via faigate)",       "contextWindow": 128000,  "maxTokens": 8000},
        {"id": "image-provider",      "name": "Image Provider (via faigate)",     "contextWindow": 128000,  "maxTokens": 8000},
        {"id": "openrouter-fallback", "name": "OpenRouter Fallback (via faigate)","contextWindow": 128000,  "maxTokens": 8000},
    ]
}

if "${fg_set_default}" == "yes":
    ad = cfg.setdefault("agents", {}).setdefault("defaults", {})
    ad.setdefault("model",      {})["primary"] = "faigate/auto"
    ad.setdefault("imageModel", {})["primary"] = "faigate/auto"
    ad["models"] = {
        "faigate/auto":                {"alias": "auto"},
        "faigate/deepseek-chat":       {"alias": "ds"},
        "faigate/deepseek-reasoner":   {"alias": "r1"},
        "faigate/gemini-flash-lite":   {"alias": "lite"},
        "faigate/gemini-flash":        {"alias": "flash"},
        "faigate/local-worker":        {"alias": "local"},
        "faigate/image-provider":      {"alias": "img"},
        "faigate/openrouter-fallback": {"alias": "or"},
    }
    ad.setdefault("subagents", {})["model"] = "faigate/auto"
    if "heartbeat" in ad:
        ad["heartbeat"]["model"] = "faigate/gemini-flash-lite"

if "${remove_legacy}" == "yes":
    providers = cfg.get("models", {}).get("providers", {})
    providers.pop("foundrygate", None)
    providers.pop("clawgate", None)

with open("${oc_json}", "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print("OK")
PYEOF

    if sudo python3 "$tmppy"; then
        success "faigate provider written to ${oc_json}"
        [[ "$remove_legacy" == "yes" ]] && info "  legacy foundrygate/clawgate entries removed"
    else
        warn "Failed to patch ${oc_json}"
    fi
    rm -f "$tmppy"
    echo ""

    # ── faigate OpenClaw Skill ─────────────────────────────────────────────────
    info "── faigate Skill for OpenClaw"
    local faigate_dir="/opt/faigrid/faigate"
    # On macOS, faigate skills are installed in Homebrew share
    local _brew_share
    _brew_share="$(brew --prefix 2>/dev/null)/share/faigate"
    local skill_src="${faigate_dir}/skills/faigate/SKILL.md"
    [[ ! -f "$skill_src" && -f "${_brew_share}/skills/faigate/SKILL.md" ]] \
        && skill_src="${_brew_share}/skills/faigate/SKILL.md"
    local skills_dir="/var/lib/openclaw/.openclaw-prod/skills"

    if ! sudo test -f "$skill_src" 2>/dev/null; then
        info "  faigate skill not found (${skill_src}) — install faigate first."
    else
        printf "  Install /faigate skill from fusionAIze Gate repo? (y/N): "
        read -r install_skill
        if [[ "${install_skill:-N}" =~ ^[Yy]$ ]]; then
            sudo mkdir -p "$skills_dir"
            sudo mkdir -p "${skills_dir}/faigate"
            sudo cp "$skill_src" "${skills_dir}/faigate/SKILL.md"
            sudo chown -R openclaw:openclaw "$skills_dir" 2>/dev/null || true
            success "Skill installed → ${skills_dir}/faigate/SKILL.md"
            info "  Available commands: /faigate stats | health | daily | route | traces | recent"
        fi
    fi
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
