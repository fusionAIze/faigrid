#!/usr/bin/env bash
TOOL_NAME="foundrygate"
TOOL_CATEGORY="routers"
TOOL_DESC="Main AI Routing Gateway (typelicious)"
TOOL_TYPE="git"

INSTALL_DIR="/opt/fusionaize-nexus/foundrygate"

tool_install() {
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "FoundryGate already cloned in $INSTALL_DIR"
    else
        sudo git clone https://github.com/typelicious/FoundryGate "$INSTALL_DIR"
        echo "Check $INSTALL_DIR/README.md for docker launch instructions."
    fi
}
tool_update() {
    if [[ -d "$INSTALL_DIR" ]]; then
        ( cd "$INSTALL_DIR" && sudo git pull )
    else
        echo "FoundryGate not found in $INSTALL_DIR."
    fi
}
tool_status() {
    if [[ -d "$INSTALL_DIR" ]]; then
        local rev
        rev=$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        echo "Installed (${rev})"
    else
        echo "Not installed"
    fi
}
tool_uninstall() { sudo rm -rf "${INSTALL_DIR}"; }

tool_configure() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        warn "FoundryGate is not installed. Run Install first."
        return 1
    fi

    local env_file="${INSTALL_DIR}/.env"
    local example_file="${INSTALL_DIR}/.env.example"

    # Bootstrap .env from example if missing
    if [[ ! -f "$env_file" ]] && [[ -f "$example_file" ]]; then
        sudo cp "$example_file" "$env_file"
        sudo chmod 600 "$env_file"
        info "Created ${env_file} from .env.example"
    elif [[ ! -f "$env_file" ]]; then
        sudo touch "$env_file"
        sudo chmod 600 "$env_file"
    fi

    info "Configuring FoundryGate — writing to ${env_file}"
    info "Press Enter to keep an existing value."

    # Read a value and patch a key in the .env file.
    # Falls back to nexus.env if the key is absent from the .env file.
    _fg_set_key() {
        local key="$1" label="$2" silent="${3:-no}"
        local current nexus_val val hint tmp
        current=$(sudo grep "^${key}=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "")
        nexus_val=$(nexus_read_env "$key" 2>/dev/null || echo "")
        if [[ "$silent" == "yes" ]]; then
            if [[ -n "$current" ]]; then
                hint="$(nexus_mask "$current")"
            elif [[ -n "$nexus_val" ]]; then
                hint="nexus: $(nexus_mask "$nexus_val")"
            else
                hint="not set"
            fi
            printf "  %s [%s]: " "$label" "$hint"
            read -r -s val; echo ""
        else
            if [[ -n "$current" ]]; then
                hint="$current"
            elif [[ -n "$nexus_val" ]]; then
                hint="nexus: $nexus_val"
            else
                hint="not set"
            fi
            printf "  %s [%s]: " "$label" "$hint"
            read -r val
        fi
        if [[ -z "$val" ]]; then
            if [[ -z "$current" ]] && [[ -n "$nexus_val" ]]; then
                val="$nexus_val"
                info "  ↳ adopted from nexus.env"
            else
                return 0
            fi
        fi
        tmp=$(mktemp)
        grep -v "^${key}=" "$env_file" > "$tmp" 2>/dev/null || true
        printf '%s=%s\n' "$key" "$val" >> "$tmp"
        sudo mv "$tmp" "$env_file"
        sudo chmod 600 "$env_file"
    }

    info "── LLM API Keys ──────────────────────────────"
    _fg_set_key "ANTHROPIC_API_KEY"  "ANTHROPIC_API_KEY"  "yes"
    _fg_set_key "OPENAI_API_KEY"     "OPENAI_API_KEY"     "yes"
    _fg_set_key "GEMINI_API_KEY"     "GEMINI_API_KEY"     "yes"
    _fg_set_key "DEEPSEEK_API_KEY"   "DEEPSEEK_API_KEY"   "yes"
    _fg_set_key "OPENROUTER_API_KEY" "OPENROUTER_API_KEY" "yes"

    info "── Image Provider ────────────────────────────"
    _fg_set_key "FAL_API_KEY"        "FAL_API_KEY (fal.ai images)" "yes"

    info "── Gateway Settings ──────────────────────────"
    _fg_set_key "FOUNDRYGATE_PORT"   "HTTP port (default 8080)" "no"

    success "FoundryGate .env updated. Run 'docker compose up -d' in ${INSTALL_DIR} to apply."
}
