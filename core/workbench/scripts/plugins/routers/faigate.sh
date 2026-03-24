#!/usr/bin/env bash
TOOL_NAME="faigate"
TOOL_CATEGORY="routers"
TOOL_DESC="fusionAIze Gate — Multi-client AI Routing Gateway"
TOOL_TYPE="git"
TOOL_SERVICE="faigate"

INSTALL_DIR="/opt/faigrid/faigate"
FAIGATE_PORT="${FAIGATE_PORT:-8090}"

# ── macOS / Homebrew detection ─────────────────────────────────────────────────
_FAIGATE_IS_BREW=false
_BREW_PREFIX="/opt/homebrew"
if [[ "$(uname)" == "Darwin" ]]; then
    _BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
    if brew list faigate >/dev/null 2>&1; then
        _FAIGATE_IS_BREW=true
    fi
fi

# Path helpers — always call these rather than hardcoding paths.
_fg_config_dir()  { $_FAIGATE_IS_BREW && echo "${_BREW_PREFIX}/etc/faigate" || echo "$INSTALL_DIR"; }
_fg_config_yaml() { echo "$(_fg_config_dir)/config.yaml"; }
_fg_env_file()    { $_FAIGATE_IS_BREW && echo "${_BREW_PREFIX}/etc/faigate/faigate.env" || echo "${INSTALL_DIR}/.env"; }
_fg_script()      {
    # On Homebrew, scripts are installed as binaries in PATH.
    # On Linux, they live in $INSTALL_DIR/scripts/.
    local name="$1"
    if $_FAIGATE_IS_BREW; then
        command -v "$name" 2>/dev/null || echo ""
    else
        local s="${INSTALL_DIR}/scripts/${name}"
        [[ -f "$s" ]] && echo "$s" || echo ""
    fi
}

# ── Lifecycle ──────────────────────────────────────────────────────────────────

tool_install() {
    if $_FAIGATE_IS_BREW || brew list faigate >/dev/null 2>&1; then
        echo "fusionAIze Gate already installed via Homebrew."
        return 0
    fi

    if [[ "$(uname)" == "Darwin" ]]; then
        info "Installing via Homebrew…"
        brew tap fusionAIze/faigate 2>/dev/null || true
        brew install faigate
        success "fusionAIze Gate installed via Homebrew."
        info "Start with: brew services start faigate"
        return 0
    fi

    # Linux: git clone
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "fusionAIze Gate already cloned in $INSTALL_DIR"
    else
        sudo git clone https://github.com/fusionAIze/faigate "$INSTALL_DIR"
        echo "Check $INSTALL_DIR/README.md for docker launch instructions."
    fi
}

tool_update() {
    if $_FAIGATE_IS_BREW; then
        info "Upgrading via Homebrew…"
        brew upgrade faigate
        success "fusionAIze Gate upgraded."
        return 0
    fi
    if [[ -d "$INSTALL_DIR" ]]; then
        ( cd "$INSTALL_DIR" && sudo git pull )
    else
        echo "fusionAIze Gate not found in $INSTALL_DIR."
    fi
}

tool_status() {
    if $_FAIGATE_IS_BREW; then
        local ver
        ver=$(faigate --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
        if curl -sf "http://127.0.0.1:${FAIGATE_PORT}/health" >/dev/null 2>&1; then
            echo "Installed (Homebrew v${ver}, running)"
        else
            echo "Installed (Homebrew v${ver}, stopped)"
        fi
        return 0
    fi

    if [[ ! -d "$INSTALL_DIR" ]]; then
        echo "Not installed"
        return
    fi
    local rev
    rev=$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    if curl -sf "http://127.0.0.1:${FAIGATE_PORT}/health" >/dev/null 2>&1; then
        echo "Installed (${rev}, running)"
    else
        echo "Installed (${rev}, stopped)"
    fi
}

tool_uninstall() {
    if $_FAIGATE_IS_BREW; then
        brew uninstall faigate
        return 0
    fi
    sudo rm -rf "${INSTALL_DIR}"
}

# ── Configure ──────────────────────────────────────────────────────────────────

tool_configure() {
    if ! $_FAIGATE_IS_BREW && [[ ! -d "$INSTALL_DIR" ]]; then
        warn "fusionAIze Gate is not installed. Run Install first."
        return 1
    fi

    local config
    config="$(_fg_config_yaml)"

    echo ""
    printf "  ${C_BOLD}fusionAIze Gate — Configuration${C_RESET}\n\n"
    printf "    ${C_BOLD}1)${C_RESET}  Config Wizard      ${C_DIM}Providers, routing modes, client profiles${C_RESET}\n"
    printf "    ${C_BOLD}2)${C_RESET}  Doctor             ${C_DIM}Validate current config.yaml${C_RESET}\n"
    printf "    ${C_BOLD}3)${C_RESET}  Provider Catalog   ${C_DIM}Browse available providers${C_RESET}\n"
    printf "    ${C_BOLD}4)${C_RESET}  Health Check       ${C_DIM}Gateway status and provider latency${C_RESET}\n"
    printf "    ${C_BOLD}5)${C_RESET}  API Keys           ${C_DIM}Set provider API keys in .env${C_RESET}\n"
    printf "    ${C_BOLD}6)${C_RESET}  Stats              ${C_DIM}Usage stats via faigate-stats${C_RESET}\n"
    echo ""
    read -r -p "  ▸ Choice (c = cancel): " cfg_choice
    echo ""

    case "$cfg_choice" in
        1) _faigate_wizard "$config" ;;
        2) _faigate_doctor ;;
        3) _faigate_provider_catalog ;;
        4) _faigate_health ;;
        5) _faigate_api_keys ;;
        6) _faigate_stats ;;
        c|C|"") info "Cancelled."; return ;;
        *) warn "Invalid choice."; return ;;
    esac
}

# ── Wizard ─────────────────────────────────────────────────────────────────────

_faigate_wizard() {
    local config="$1"
    local wizard
    wizard="$(_fg_script faigate-config-wizard)"

    if [[ -z "$wizard" ]]; then
        warn "faigate-config-wizard not found."
        $_FAIGATE_IS_BREW \
            && warn "Try: brew upgrade faigate" \
            || warn "Run git pull in ${INSTALL_DIR} to update."
        return 1
    fi

    printf "  ${C_DIM}The wizard generates or updates config.yaml with providers, routing\n"
    printf "  modes, and client profiles based on your use-case.${C_RESET}\n\n"

    # ── Purpose
    printf "  ${C_BOLD}Purpose${C_RESET}  ${C_DIM}(1=general  2=coding  3=quality  4=free)${C_RESET}\n"
    read -r -p "  ▸ [general]: " purpose_in
    local purpose
    case "${purpose_in:-1}" in
        1|general)  purpose="general"  ;;
        2|coding)   purpose="coding"   ;;
        3|quality)  purpose="quality"  ;;
        4|free)     purpose="free"     ;;
        *)          purpose="general"  ;;
    esac
    echo ""

    # ── Client profile
    printf "  ${C_BOLD}Client Profile${C_RESET}  ${C_DIM}Preset: openclaw | n8n | cli | generic | swe-af | paperclip | ship-faster${C_RESET}\n"
    read -r -p "  ▸ [generic]: " client
    client="${client:-generic}"
    echo ""

    # ── Show candidates first
    printf "  ${C_DIM}Fetching provider candidates for purpose=%s client=%s …${C_RESET}\n\n" \
        "$purpose" "$client"
    bash "$wizard" \
        --purpose "$purpose" \
        --client "$client" \
        --list-candidates 2>/dev/null || true
    echo ""

    # ── Provider selection
    printf "  ${C_BOLD}Select providers${C_RESET}  ${C_DIM}comma-separated IDs from list above, or 'all', or Enter for recommendations${C_RESET}\n"
    read -r -p "  ▸ Selection: " prov_select
    echo ""

    # ── Dry-run or write
    printf "  ${C_BOLD}Apply mode${C_RESET}\n"
    printf "    ${C_BOLD}1)${C_RESET}  Dry-run only    ${C_DIM}Preview changes, no writes${C_RESET}\n"
    printf "    ${C_BOLD}2)${C_RESET}  Write config    ${C_DIM}Update config.yaml (backup created automatically)${C_RESET}\n"
    read -r -p "  ▸ [1]: " apply_mode
    echo ""

    # Build base args
    local cmd_args=("--purpose" "$purpose" "--client" "$client")
    if [[ -f "$config" ]]; then
        cmd_args+=(
            "--current-config" "$config"
            "--merge-existing"
            "--apply" "recommended_add,recommended_replace,recommended_mode_changes"
        )
    fi
    if [[ -n "$prov_select" && "$prov_select" != "all" ]]; then
        cmd_args+=("--select" "$prov_select")
    fi

    case "${apply_mode:-1}" in
        2)
            local backup_suffix=".bak-$(date +%Y%m%d%H%M%S)"
            cmd_args+=("--write" "$config" "--write-backup" "--backup-suffix" "$backup_suffix")
            info "Running wizard (write mode — backup suffix: ${backup_suffix})…"
            bash "$wizard" "${cmd_args[@]}"
            success "config.yaml updated: ${config}"
            echo ""
            printf "  Restart faigate to apply changes? [y/N]: "
            read -r restart_choice
            if [[ "${restart_choice:-N}" =~ ^[Yy]$ ]]; then
                _faigate_restart
            fi
            ;;
        *)
            cmd_args+=("--dry-run-summary")
            info "Running wizard (dry-run)…"
            bash "$wizard" "${cmd_args[@]}"
            echo ""
            info "Dry-run complete. Re-run and choose option 2 to apply."
            ;;
    esac
}

# ── Doctor ─────────────────────────────────────────────────────────────────────

_faigate_doctor() {
    local doctor
    doctor="$(_fg_script faigate-doctor)"
    if [[ -z "$doctor" ]]; then
        warn "faigate-doctor not found."
        $_FAIGATE_IS_BREW && warn "Try: brew upgrade faigate" || warn "Run git pull in ${INSTALL_DIR}"
        return 1
    fi
    info "Running faigate-doctor…"
    bash "$doctor" 2>&1 || true
}

# ── Provider catalog ───────────────────────────────────────────────────────────

_faigate_provider_catalog() {
    local disc
    disc="$(_fg_script faigate-provider-discovery)"
    if [[ -n "$disc" ]]; then
        bash "$disc" 2>&1 | head -80 || true
        return
    fi
    # Fallback: hit the local API if gateway is running
    if curl -sf "http://127.0.0.1:${FAIGATE_PORT}/api/provider-catalog" \
            | python3 -m json.tool 2>/dev/null; then
        return
    fi
    warn "Provider discovery script not found and gateway not reachable."
    return 1
}

# ── Health check ───────────────────────────────────────────────────────────────

_faigate_health() {
    info "Checking fusionAIze Gate at http://127.0.0.1:${FAIGATE_PORT}…"
    if curl -sf "http://127.0.0.1:${FAIGATE_PORT}/health" \
            | python3 -m json.tool 2>/dev/null; then
        echo ""
        info "Model list:"
        curl -sf "http://127.0.0.1:${FAIGATE_PORT}/v1/models" \
            | python3 -c "
import json, sys
data = json.load(sys.stdin)
for m in data.get('data', []):
    print('  ', m.get('id',''))
" 2>/dev/null || true
        echo ""
        info "Dashboard: http://127.0.0.1:${FAIGATE_PORT}/dashboard"
    else
        warn "Gateway not reachable at port ${FAIGATE_PORT}."
        if $_FAIGATE_IS_BREW; then
            info "Start with: brew services start faigate"
        else
            info "Start it via Docker: cd ${INSTALL_DIR} && docker compose up -d"
        fi
    fi
}

# ── Stats ──────────────────────────────────────────────────────────────────────

_faigate_stats() {
    local stats_bin
    stats_bin="$(_fg_script faigate-stats)"
    if [[ -z "$stats_bin" ]]; then
        warn "faigate-stats not found."
        return 1
    fi
    info "fusionAIze Gate — Usage Stats"
    echo ""
    bash "$stats_bin" 2>&1 || true
    echo ""
    info "Dashboard: http://127.0.0.1:${FAIGATE_PORT}/dashboard"
}

# ── API Keys ───────────────────────────────────────────────────────────────────

_faigate_api_keys() {
    local env_file
    env_file="$(_fg_env_file)"
    local example_file
    if $_FAIGATE_IS_BREW; then
        example_file="${_BREW_PREFIX}/share/faigate/.env.example"
    else
        example_file="${INSTALL_DIR}/.env.example"
    fi

    # Create env file if absent
    if [[ ! -f "$env_file" ]] && [[ -f "$example_file" ]]; then
        if $_FAIGATE_IS_BREW; then
            cp "$example_file" "$env_file"
            chmod 600 "$env_file"
        else
            sudo cp "$example_file" "$env_file"
            sudo chmod 600 "$env_file"
        fi
        info "Created ${env_file} from .env.example"
    elif [[ ! -f "$env_file" ]]; then
        if $_FAIGATE_IS_BREW; then
            touch "$env_file"; chmod 600 "$env_file"
        else
            sudo touch "$env_file"; sudo chmod 600 "$env_file"
        fi
    fi

    info "Writing API keys to ${env_file} — press Enter to keep current value."
    echo ""

    _set_key() {
        local key="$1" label="$2" silent="${3:-yes}"
        local current grid_val val hint tmp
        if $_FAIGATE_IS_BREW; then
            current=$(grep "^${key}=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "")
        else
            current=$(sudo grep "^${key}=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "")
        fi
        grid_val=$(grid_read_env "$key" 2>/dev/null || echo "")
        if [[ -n "$current" ]]; then
            hint="$(grid_mask "$current")"
        elif [[ -n "$grid_val" ]]; then
            hint="${C_DIM}from grid.env${C_RESET}"
        else
            hint="${C_DIM}(not set)${C_RESET}"
        fi
        printf "  %-28s [%b]: " "$label" "$hint"
        if [[ "$silent" == "yes" ]]; then read -r -s val; echo ""; else read -r val; fi
        if [[ -z "$val" ]]; then
            [[ -z "$current" && -n "$grid_val" ]] && val="$grid_val" && info "  ↳ adopted from grid.env"
            [[ -z "$val" ]] && return 0
        fi
        tmp=$(mktemp)
        if $_FAIGATE_IS_BREW; then
            grep -v "^${key}=" "$env_file" > "$tmp" 2>/dev/null || true
            printf '%s=%s\n' "$key" "$val" >> "$tmp"
            mv "$tmp" "$env_file"
            chmod 600 "$env_file"
        else
            sudo grep -v "^${key}=" "$env_file" > "$tmp" 2>/dev/null || true
            printf '%s=%s\n' "$key" "$val" >> "$tmp"
            sudo mv "$tmp" "$env_file"
            sudo chmod 600 "$env_file"
        fi
    }

    info "── LLM Providers"
    _set_key "ANTHROPIC_API_KEY"  "ANTHROPIC_API_KEY"  "yes"
    _set_key "OPENAI_API_KEY"     "OPENAI_API_KEY"     "yes"
    _set_key "GEMINI_API_KEY"     "GEMINI_API_KEY"     "yes"
    _set_key "DEEPSEEK_API_KEY"   "DEEPSEEK_API_KEY"   "yes"
    _set_key "OPENROUTER_API_KEY" "OPENROUTER_API_KEY" "yes"
    echo ""
    info "── Image Providers"
    _set_key "FAL_API_KEY"        "FAL_API_KEY (fal.ai)" "yes"
    echo ""
    info "── Gateway"
    _set_key "FAIGATE_PORT"       "HTTP port"            "no"
    echo ""
    if $_FAIGATE_IS_BREW; then
        success ".env updated at ${env_file}. Restart faigate to apply:"
        info "  brew services restart faigate"
    else
        success ".env updated. Restart faigate to apply (docker compose up -d in ${INSTALL_DIR})."
    fi
}

# ── Restart helper ─────────────────────────────────────────────────────────────

_faigate_restart() {
    if $_FAIGATE_IS_BREW; then
        brew services restart faigate
        success "faigate restarted via Homebrew services."
        return 0
    fi
    if systemctl is-active --quiet faigate.service 2>/dev/null; then
        sudo systemctl restart faigate.service
        success "faigate.service restarted."
    elif [[ -f "${INSTALL_DIR}/docker-compose.yml" ]] || \
         [[ -f "${INSTALL_DIR}/compose.yaml" ]]; then
        ( cd "$INSTALL_DIR" && docker compose restart )
        success "faigate Docker container restarted."
    else
        info "Manual restart required — see ${INSTALL_DIR}/README.md"
    fi
}
