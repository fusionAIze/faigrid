#!/usr/bin/env bash
TOOL_NAME="antigravity"
TOOL_CATEGORY="clis"
TOOL_DESC="Antigravity AI IDE — Google"
TOOL_TYPE="apt|dnf"
FAIGATE_CLIENT="antigravity"
# https://antigravity.google/download/linux

_detect_pkg_manager() {
    if   command -v apt-get >/dev/null 2>&1; then echo "apt"
    elif command -v dnf     >/dev/null 2>&1; then echo "dnf"
    elif command -v yum     >/dev/null 2>&1; then echo "yum"
    else                                          echo "unknown"
    fi
}

_install_deb() {
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg \
        | sudo gpg --dearmor --yes \
            -o /etc/apt/keyrings/antigravity-repo-key.gpg
    echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] \
https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ \
antigravity-debian main" \
        | sudo tee /etc/apt/sources.list.d/antigravity.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y antigravity
}

_install_rpm() {
    sudo tee /etc/yum.repos.d/antigravity.repo > /dev/null << 'EOF'
[antigravity-rpm]
name=Antigravity RPM Repository
baseurl=https://us-central1-yum.pkg.dev/projects/antigravity-auto-updater-dev/antigravity-rpm
enabled=1
gpgcheck=0
EOF
    local pm
    pm=$(_detect_pkg_manager)
    sudo "${pm}" makecache
    sudo "${pm}" install -y antigravity
}

tool_install() {
    local pm
    pm=$(_detect_pkg_manager)
    case "$pm" in
        apt)       _install_deb ;;
        dnf|yum)   _install_rpm ;;
        *)  echo "[antigravity] Unsupported package manager." >&2
            echo "[antigravity] See https://antigravity.google/download/linux" >&2
            return 1 ;;
    esac
}

tool_update() {
    local pm
    pm=$(_detect_pkg_manager)
    case "$pm" in
        apt)      sudo apt-get install -y --only-upgrade antigravity ;;
        dnf|yum)  sudo "${pm}" upgrade -y antigravity ;;
        *)  echo "[antigravity] Update not supported on this system." >&2; return 1 ;;
    esac
}

tool_status() {
    if command -v agy >/dev/null 2>&1; then
        local ver
        ver=$(agy --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}

tool_uninstall() {
    local pm
    pm=$(_detect_pkg_manager)
    case "$pm" in
        apt)
            sudo apt-get remove -y antigravity
            sudo rm -f /etc/apt/keyrings/antigravity-repo-key.gpg \
                       /etc/apt/sources.list.d/antigravity.list
            ;;
        dnf|yum)
            sudo "${pm}" remove -y antigravity
            sudo rm -f /etc/yum.repos.d/antigravity.repo
            ;;
    esac
}

tool_configure() {
    local current
    current=$(grid_read_env "GEMINI_API_KEY")
    info "Antigravity AI IDE uses the Gemini API."
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
    info "── fusionAIze Gate Routing (Antigravity)"
    if ! curl -sf "http://127.0.0.1:${fg_port}/health" >/dev/null 2>&1; then
        warn "  fusionAIze Gate not reachable at port ${fg_port} — skipping."
        return 0
    fi
    info "  Gate is running at ${fg_url}"

    # Antigravity supports custom OpenAI-compat endpoint via OPENAI_API_BASE
    local cur_base
    cur_base=$(grid_read_env "OPENAI_API_BASE" 2>/dev/null || echo "")
    local routed="no"
    [[ "$cur_base" == "$fg_url" ]] && routed="yes"

    printf "  Route Antigravity through faigate (OPENAI_API_BASE)? current=[%s] (y/N): " "$routed"
    read -r route_choice

    if [[ "${route_choice:-N}" =~ ^[Yy]$ ]]; then
        grid_write_env "OPENAI_API_BASE" "$fg_url"
        grid_ensure_sourced
        success "  OPENAI_API_BASE → ${fg_url} (saved to grid.env)"
        info "  Antigravity will use faigate's 'antigravity' client profile."
        info "  Preferred: gemini-flash-lite, gemini-flash, gemini-pro"
        echo ""
        info "  Note: Also configure Antigravity's custom endpoint in its IDE settings"
        info "  to point to ${fg_url} with apiKey=local for full integration."
    elif [[ "$routed" == "yes" ]]; then
        printf "  Disable faigate routing for Antigravity? (y/N): "
        read -r disable_choice
        if [[ "${disable_choice:-N}" =~ ^[Yy]$ ]]; then
            local tmp genv
            genv="${HOME}/.config/faigrid/grid.env"
            tmp=$(mktemp)
            grep -v "^OPENAI_API_BASE=" "$genv" > "$tmp" 2>/dev/null || true
            mv "$tmp" "$genv"
            success "  OPENAI_API_BASE removed — Antigravity routes directly."
        fi
    fi
}
