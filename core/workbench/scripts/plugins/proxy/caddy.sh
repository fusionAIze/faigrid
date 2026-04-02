#!/usr/bin/env bash
TOOL_NAME="caddy"
TOOL_CATEGORY="proxy"
TOOL_DESC="Caddy Reverse Proxy (Edge Node)"
TOOL_TYPE="systemd"
TOOL_SERVICE="caddy"
TOOL_UPDATE_TYPE="github"
TOOL_UPDATE_REPO="caddyserver/caddy"

# Registry location (matches install.sh LOCAL_REGISTRY)
_CADDY_REGISTRY="${HOME}/.config/faigrid/registry"

# ── Helpers ────────────────────────────────────────────────────────────────────

# Read a single key from a role's .state file
_caddy_read_state() {
    local role="$1" key="$2"
    local f="${_CADDY_REGISTRY}/${role}.state"
    [[ -f "$f" ]] || return 0
    grep "^${key}=" "$f" 2>/dev/null | head -1 | cut -d'=' -f2 || true
}

# Return SSH_TARGET for a registered role, or empty string
_caddy_ssh_for() {
    _caddy_read_state "$1" "SSH_TARGET"
}

# Run a command on the edge node via SSH; returns 1 if unreachable
_edge_ssh() {
    local ssh_edge="$1"; shift
    ssh -q -o ConnectTimeout=8 -o BatchMode=yes "$ssh_edge" "$@" 2>/dev/null
}

# ── Lifecycle ──────────────────────────────────────────────────────────────────

tool_install() {
    local ssh_edge
    ssh_edge=$(_caddy_ssh_for "edge")
    if [[ -z "$ssh_edge" ]]; then
        warn "No edge node registered. Register an edge node in the main orchestrator first."
        return 1
    fi

    info "Installing Caddy on edge node (${ssh_edge})…"
    # shellcheck disable=SC2087
    ssh -t "$ssh_edge" << 'REMOTE'
if command -v caddy &>/dev/null; then
    echo "Caddy already installed: $(caddy version 2>/dev/null | head -1)"
    exit 0
fi
sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt-get update -y
sudo apt-get install -y caddy
sudo systemctl enable caddy
echo "Caddy installed: $(caddy version 2>/dev/null | head -1)"
REMOTE
    success "Caddy installation complete on ${ssh_edge}"
    info "Run Configure (option 5) to deploy your Caddyfile."
}

tool_update() {
    local ssh_edge
    ssh_edge=$(_caddy_ssh_for "edge")
    if [[ -z "$ssh_edge" ]]; then
        warn "No edge node registered."; return 1
    fi
    info "Updating Caddy on ${ssh_edge}…"
    # shellcheck disable=SC2087
    ssh -t "$ssh_edge" << 'REMOTE'
sudo apt-get update -y
sudo apt-get install -y --only-upgrade caddy
caddy version 2>/dev/null | head -1 || true
sudo systemctl reload-or-restart caddy
REMOTE
    success "Caddy updated."
}

tool_status() {
    local ssh_edge
    ssh_edge=$(_caddy_ssh_for "edge")
    if [[ -z "$ssh_edge" ]]; then
        echo "Not configured (no edge node)"
        return
    fi

    local state ver
    state=$(_edge_ssh "$ssh_edge" "systemctl is-active caddy 2>/dev/null || echo 'inactive'" || echo "unreachable")
    ver=$(  _edge_ssh "$ssh_edge" "caddy version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true")

    case "$state" in
        active)   echo "Installed (Running${ver:+ ${ver}})" ;;
        inactive) echo "Installed (Stopped)" ;;
        failed)   echo "Installed (Failed)" ;;
        *)        echo "Not installed" ;;
    esac
}

tool_uninstall() {
    local ssh_edge
    ssh_edge=$(_caddy_ssh_for "edge")
    if [[ -z "$ssh_edge" ]]; then
        warn "No edge node registered."; return 1
    fi
    warn "This will stop Caddy and remove its package on the edge node."
    printf "  Proceed? (y/N): "; read -r confirm
    [[ "${confirm:-N}" =~ ^[Yy]$ ]] || { info "Aborted."; return 0; }
    ssh -t "$ssh_edge" "sudo systemctl stop caddy; sudo apt-get remove -y caddy"
    success "Caddy removed from ${ssh_edge}"
}

# ── Configure ──────────────────────────────────────────────────────────────────

tool_configure() {
    local ssh_edge ssh_core
    ssh_edge=$(_caddy_ssh_for "edge")
    ssh_core=$(_caddy_ssh_for "core")

    if [[ -z "$ssh_edge" ]]; then
        warn "No edge node registered. Register edge node first via the main orchestrator."
        return 1
    fi

    info "── Caddy reverse proxy — node targets"
    printf "  ${C_DIM}Edge : %s${C_RESET}\n" "$ssh_edge"
    printf "  ${C_DIM}Core : %s${C_RESET}\n" "${ssh_core:-(not registered — enter IP manually)}"
    echo ""

    # ── Core internal IP ──────────────────────────────────────────────────────
    # Prefer: IP resolved from core SSH target; fallback: existing Caddyfile; then ask.
    local core_ip=""
    if [[ -n "$ssh_core" ]]; then
        core_ip=$(_edge_ssh "$ssh_core" "hostname -I | awk '{print \$1}'" 2>/dev/null || true)
    fi
    local cur_core_ip
    cur_core_ip=$(_edge_ssh "$ssh_edge" \
        "grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' /etc/caddy/Caddyfile 2>/dev/null | head -1 || true" || true)

    printf "  Core internal IP  [%s]: " "${cur_core_ip:-${core_ip:-10.0.0.x}}"
    read -r input_core_ip
    core_ip="${input_core_ip:-${cur_core_ip:-$core_ip}}"
    if [[ -z "$core_ip" ]]; then
        warn "Core IP is required."; return 1
    fi

    # ── Domains ───────────────────────────────────────────────────────────────
    local cur_n8n_domain=""
    cur_n8n_domain=$(_edge_ssh "$ssh_edge" \
        "grep -E '^[a-z]' /etc/caddy/Caddyfile 2>/dev/null | grep -v '#' | head -1 | cut -d' ' -f1 || true" || true)
    local base_domain=""
    [[ -n "$cur_n8n_domain" ]] && base_domain="${cur_n8n_domain#*.}"

    echo ""
    info "── Service domains"
    printf "  n8n domain        [%s]: " "${cur_n8n_domain:-n8n.yourdomain.com}"
    read -r n8n_domain
    n8n_domain="${n8n_domain:-${cur_n8n_domain:-}}"
    if [[ -z "$n8n_domain" ]]; then
        warn "n8n domain is required."; return 1
    fi
    [[ -z "$base_domain" ]] && base_domain="${n8n_domain#*.}"

    printf "  Expose faigate?   (y/N): "; read -r expose_faigate
    local faigate_domain=""
    if [[ "${expose_faigate:-N}" =~ ^[Yy]$ ]]; then
        printf "  faigate domain    [faigate.%s]: " "$base_domain"
        read -r faigate_domain
        [[ -z "$faigate_domain" ]] && faigate_domain="faigate.${base_domain}"
    fi

    printf "  Expose openclaw?  (y/N): "; read -r expose_openclaw
    local openclaw_domain=""
    if [[ "${expose_openclaw:-N}" =~ ^[Yy]$ ]]; then
        printf "  openclaw domain   [openclaw.%s]: " "$base_domain"
        read -r openclaw_domain
        [[ -z "$openclaw_domain" ]] && openclaw_domain="openclaw.${base_domain}"
    fi

    # ── Caddyfile generation ──────────────────────────────────────────────────
    local generated_at
    generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # Build Caddyfile in a temp variable (Bash 3.2 compatible — no arrays)
    local caddyfile_content
    caddyfile_content="# fusionAIze Grid — Caddyfile
# Generated by faigrid workbench ${generated_at}

${n8n_domain} {
    reverse_proxy ${core_ip}:5678 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
    }
}"

    if [[ -n "$faigate_domain" ]]; then
        caddyfile_content="${caddyfile_content}

${faigate_domain} {
    reverse_proxy ${core_ip}:8090
}"
    fi

    if [[ -n "$openclaw_domain" ]]; then
        caddyfile_content="${caddyfile_content}

${openclaw_domain} {
    reverse_proxy ${core_ip}:18789
}"
    fi

    echo ""
    info "── Preview"
    echo "$caddyfile_content" | sed 's/^/    /'
    echo ""

    printf "  Deploy to edge (%s)? (y/N): " "$ssh_edge"
    read -r confirm_deploy
    [[ "${confirm_deploy:-N}" =~ ^[Yy]$ ]] || { info "Aborted."; return 0; }

    # Deploy: pipe Caddyfile over SSH, validate, then reload
    echo "$caddyfile_content" \
        | ssh -q "$ssh_edge" "sudo tee /etc/caddy/Caddyfile > /dev/null"

    local validate_out
    validate_out=$(ssh -q "$ssh_edge" \
        "sudo caddy validate --config /etc/caddy/Caddyfile 2>&1" || true)

    if echo "$validate_out" | grep -q "Valid"; then
        ssh -q "$ssh_edge" "sudo systemctl reload-or-restart caddy" || true
        success "Caddyfile deployed and Caddy reloaded on ${ssh_edge}"
        echo ""
        info "  https://${n8n_domain}  →  n8n (${core_ip}:5678)"
        [[ -n "$faigate_domain"  ]] && info "  https://${faigate_domain}  →  faigate (${core_ip}:8090)"
        [[ -n "$openclaw_domain" ]] && info "  https://${openclaw_domain}  →  openclaw (${core_ip}:18789)"
        echo ""
        info "  Caddy will auto-obtain TLS certificates via Let's Encrypt."
        info "  Ensure DNS A records point to the edge node's public IP."
    else
        warn "Caddy config validation failed — Caddyfile was written but service NOT reloaded."
        echo "$validate_out" | sed 's/^/    /'
        info "Fix with: ssh ${ssh_edge} 'sudo caddy validate --config /etc/caddy/Caddyfile'"
    fi
}

# ── Doctor ─────────────────────────────────────────────────────────────────────

tool_doctor() {
    local ssh_edge
    ssh_edge=$(_caddy_ssh_for "edge")
    if [[ -z "$ssh_edge" ]]; then
        warn "No edge node registered."; return
    fi

    # ── 1. Service state ──────────────────────────────────────────────────────
    info "── caddy service (${ssh_edge})"
    _edge_ssh "$ssh_edge" \
        "systemctl --no-pager status caddy 2>&1 | head -25" \
        || warn "Could not reach edge node — check SSH connectivity"
    echo ""

    # ── 2. Config validation ──────────────────────────────────────────────────
    info "── caddy config validate"
    _edge_ssh "$ssh_edge" \
        "sudo caddy validate --config /etc/caddy/Caddyfile 2>&1 || true" \
        || warn "Validation command failed"
    echo ""

    # ── 3. TLS certificates ───────────────────────────────────────────────────
    info "── TLS certificates"
    _edge_ssh "$ssh_edge" \
        "sudo find /var/lib/caddy/.local/share/caddy/certificates -name '*.crt' 2>/dev/null \
         | sed 's|.*/||' | sed 's|\.crt||' | head -20 \
         || echo '  (no certificates found yet)'" \
        || true
    echo ""

    # ── 4. Upstream connectivity from edge ────────────────────────────────────
    info "── upstream reachability (from edge → core)"
    local core_ip
    core_ip=$(_edge_ssh "$ssh_edge" \
        "grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' /etc/caddy/Caddyfile 2>/dev/null | head -1 || true" || true)

    if [[ -n "$core_ip" ]]; then
        _edge_ssh "$ssh_edge" \
            "curl -sf --max-time 5 http://${core_ip}:5678/healthz >/dev/null \
             && echo '  ✔ n8n  reachable (${core_ip}:5678)' \
             || echo '  ✘ n8n  NOT reachable (${core_ip}:5678)'" || true
        _edge_ssh "$ssh_edge" \
            "curl -sf --max-time 5 http://${core_ip}:8090/health >/dev/null \
             && echo '  ✔ faigate reachable (${core_ip}:8090)' \
             || echo '  ✘ faigate not reachable (${core_ip}:8090)'" 2>/dev/null || true
    else
        warn "Could not determine core IP from /etc/caddy/Caddyfile"
    fi
    echo ""

    # ── 5. Listening ports ────────────────────────────────────────────────────
    info "── listening ports (edge)"
    _edge_ssh "$ssh_edge" \
        "sudo ss -tlnp 2>/dev/null | grep -E ':80|:443' \
         || echo '  (no 80/443 listeners detected)'" || true
}
