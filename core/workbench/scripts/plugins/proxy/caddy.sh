#!/usr/bin/env bash
TOOL_NAME="caddy"
TOOL_CATEGORY="proxy"
TOOL_DESC="Caddy Reverse Proxy (Edge Node — internal LAN)"
TOOL_TYPE="systemd"
TOOL_SERVICE="caddy"
TOOL_UPDATE_TYPE="github"
TOOL_UPDATE_REPO="caddyserver/caddy"

_CADDY_REGISTRY="${HOME}/.config/faigrid/registry"

# ── Helpers ────────────────────────────────────────────────────────────────────

_caddy_read_state() {
    local role="$1" key="$2"
    local f="${_CADDY_REGISTRY}/${role}.state"
    [[ -f "$f" ]] || return 0
    grep "^${key}=" "$f" 2>/dev/null | head -1 | cut -d'=' -f2 || true
}

_caddy_ssh_for() { _caddy_read_state "$1" "SSH_TARGET"; }

_edge_ssh() {
    local ssh_edge="$1"; shift
    ssh -q -o ConnectTimeout=8 -o BatchMode=yes "$ssh_edge" "$@" 2>/dev/null
}

# ── Lifecycle ──────────────────────────────────────────────────────────────────

tool_install() {
    local ssh_edge
    ssh_edge=$(_caddy_ssh_for "edge")
    if [[ -z "$ssh_edge" ]]; then
        warn "No edge node registered. Register edge node first."
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
sudo apt-get update -y && sudo apt-get install -y caddy
sudo systemctl enable caddy
echo "Caddy installed: $(caddy version 2>/dev/null | head -1)"
REMOTE
    success "Caddy installed on ${ssh_edge}"
    info "Run Configure to set up .grid DNS and Caddyfile."
}

tool_update() {
    local ssh_edge
    ssh_edge=$(_caddy_ssh_for "edge")
    [[ -z "$ssh_edge" ]] && { warn "No edge node registered."; return 1; }
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
    [[ -z "$ssh_edge" ]] && { warn "No edge node registered."; return 1; }
    warn "This will stop Caddy and remove its package on ${ssh_edge}."
    printf "  Proceed? (y/N): "; read -r confirm
    [[ "${confirm:-N}" =~ ^[Yy]$ ]] || { info "Aborted."; return 0; }
    ssh -t "$ssh_edge" "sudo systemctl stop caddy; sudo apt-get remove -y caddy"
    success "Caddy removed from ${ssh_edge}"
}

# ── Configure ──────────────────────────────────────────────────────────────────
#
# Sets up Caddy as an internal LAN reverse proxy using the .grid TLD.
# Pi-hole on the edge node is configured to resolve *.grid to the edge LAN IP.
# The workstation must use Pi-hole as its DNS server (or add the .grid entries
# manually to /etc/hosts).
#
# Service map (.grid hostnames → core ports):
#   n8n.grid       → core:5678
#   faigate.grid   → core:8090
#   openclaw.grid  → core:18789
#   codenomad.grid → core:4000  (or configured port)

tool_configure() {
    local ssh_edge ssh_core
    ssh_edge=$(_caddy_ssh_for "edge")
    ssh_core=$(_caddy_ssh_for "core")

    if [[ -z "$ssh_edge" ]]; then
        warn "No edge node registered."; return 1
    fi

    info "── Caddy LAN proxy — internal .grid setup"
    printf "  ${C_DIM}Edge : %s${C_RESET}\n" "$ssh_edge"
    printf "  ${C_DIM}Core : %s${C_RESET}\n" "${ssh_core:-(not registered)}"
    echo ""

    # ── Edge LAN IP ───────────────────────────────────────────────────────────
    # The LAN IP is what Pi-hole will resolve *.grid to.
    local edge_lan_ip
    edge_lan_ip=$(_edge_ssh "$ssh_edge" "hostname -I | awk '{print \$1}'" || true)

    local cur_edge_ip
    cur_edge_ip=$(_edge_ssh "$ssh_edge" \
        "grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' /etc/caddy/Caddyfile 2>/dev/null | head -1 || true" || true)

    printf "  Edge LAN IP  [%s]: " "${edge_lan_ip:-192.168.x.x}"
    read -r input_edge_ip
    edge_lan_ip="${input_edge_ip:-${edge_lan_ip:-}}"
    if [[ -z "$edge_lan_ip" ]]; then
        warn "Edge LAN IP required."; return 1
    fi

    # ── Core internal IP ──────────────────────────────────────────────────────
    local core_ip=""
    if [[ -n "$ssh_core" ]]; then
        core_ip=$(_edge_ssh "$ssh_core" "hostname -I | awk '{print \$1}'" 2>/dev/null || true)
    fi
    local cur_core_ip
    cur_core_ip=$(_edge_ssh "$ssh_edge" \
        "grep -oE 'reverse_proxy ([0-9.]+)' /etc/caddy/Caddyfile 2>/dev/null | head -1 | awk '{print \$2}' || true" || true)

    printf "  Core LAN IP  [%s]: " "${cur_core_ip:-${core_ip:-10.0.0.x}}"
    read -r input_core_ip
    core_ip="${input_core_ip:-${cur_core_ip:-$core_ip}}"
    if [[ -z "$core_ip" ]]; then
        warn "Core LAN IP required."; return 1
    fi

    # ── Services to expose ────────────────────────────────────────────────────
    echo ""
    info "── Services to expose on .grid (all on ${core_ip})"
    printf "  n8n           port  [5678]: "; read -r n8n_port
    n8n_port="${n8n_port:-5678}"

    printf "  faigate       port  [8090]: "; read -r faigate_port
    faigate_port="${faigate_port:-8090}"

    printf "  openclaw      port  [18789]: "; read -r openclaw_port
    openclaw_port="${openclaw_port:-18789}"

    printf "  codenomad?  (y/N): "; read -r expose_codenomad
    local codenomad_port=""
    if [[ "${expose_codenomad:-N}" =~ ^[Yy]$ ]]; then
        printf "  codenomad     port  [4000]: "; read -r codenomad_port
        codenomad_port="${codenomad_port:-4000}"
    fi

    # ── TLS mode ──────────────────────────────────────────────────────────────
    echo ""
    info "── TLS (internal LAN)"
    printf "  ${C_DIM}Use Caddy internal CA? HTTPS in browser (recommended).${C_RESET}\n"
    printf "  ${C_DIM}Requires trusting Caddy root cert on workstation once.${C_RESET}\n"
    printf "  Enable internal TLS? (Y/n): "; read -r use_tls
    local tls_directive=""
    if [[ ! "${use_tls:-Y}" =~ ^[Nn]$ ]]; then
        tls_directive="    tls internal"
    fi

    # ── Generate Caddyfile ────────────────────────────────────────────────────
    local generated_at
    generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local cf
    cf="# fusionAIze Grid — Caddyfile (internal LAN)
# Generated ${generated_at}

n8n.grid {
${tls_directive:+${tls_directive}
}    reverse_proxy ${core_ip}:${n8n_port}
}

faigate.grid {
${tls_directive:+${tls_directive}
}    reverse_proxy ${core_ip}:${faigate_port}
}

openclaw.grid {
${tls_directive:+${tls_directive}
}    reverse_proxy ${core_ip}:${openclaw_port}
}"

    if [[ -n "$codenomad_port" ]]; then
        cf="${cf}

codenomad.grid {
${tls_directive:+${tls_directive}
}    reverse_proxy ${core_ip}:${codenomad_port}
}"
    fi

    echo ""
    info "── Preview"
    echo "$cf" | sed 's/^/    /'
    echo ""

    printf "  Deploy to edge + configure Pi-hole DNS? (y/N): "
    read -r confirm_deploy
    [[ "${confirm_deploy:-N}" =~ ^[Yy]$ ]] || { info "Aborted."; return 0; }

    # ── Deploy Caddyfile ──────────────────────────────────────────────────────
    echo "$cf" | ssh -q "$ssh_edge" "sudo tee /etc/caddy/Caddyfile > /dev/null"

    local validate_out
    validate_out=$(_edge_ssh "$ssh_edge" \
        "sudo caddy validate --config /etc/caddy/Caddyfile 2>&1" || true)

    if echo "$validate_out" | grep -qi "valid\|no errors"; then
        _edge_ssh "$ssh_edge" "sudo systemctl reload-or-restart caddy" || true
        success "Caddyfile deployed and Caddy reloaded."
    else
        warn "Caddy validation output:"
        echo "$validate_out" | sed 's/^/    /'
        warn "Caddyfile written but service NOT reloaded. Fix and run: sudo systemctl reload caddy"
    fi

    # ── Configure Pi-hole DNS ─────────────────────────────────────────────────
    info "── Pi-hole DNS entries (${edge_lan_ip} → *.grid)"
    local pihole_custom="/etc/pihole/custom.list"

    local dns_entries
    dns_entries="${edge_lan_ip} n8n.grid
${edge_lan_ip} faigate.grid
${edge_lan_ip} openclaw.grid"
    [[ -n "$codenomad_port" ]] && dns_entries="${dns_entries}
${edge_lan_ip} codenomad.grid"

    # Remove existing .grid entries, then append fresh ones
    # shellcheck disable=SC2029
    ssh -q "$ssh_edge" "
        sudo touch '${pihole_custom}'
        sudo sed -i '/\\.grid$/d' '${pihole_custom}'
        printf '%s\n' $(printf '%q' "${dns_entries}") | sudo tee -a '${pihole_custom}' > /dev/null
        sudo pihole restartdns 2>/dev/null || sudo systemctl restart pihole-FTL 2>/dev/null || true
    " && success "Pi-hole DNS entries written and restarted." \
      || warn "Pi-hole DNS update failed — add entries manually to ${pihole_custom} on edge."

    echo ""
    success "Internal LAN proxy configured."
    info "  http${tls_directive:+s}://n8n.grid       → ${core_ip}:${n8n_port}"
    info "  http${tls_directive:+s}://faigate.grid   → ${core_ip}:${faigate_port}"
    info "  http${tls_directive:+s}://openclaw.grid  → ${core_ip}:${openclaw_port}"
    [[ -n "$codenomad_port" ]] && \
    info "  http${tls_directive:+s}://codenomad.grid → ${core_ip}:${codenomad_port}"
    echo ""
    info "  ${C_BOLD}Workstation DNS${C_RESET}: set primary DNS to ${edge_lan_ip} (Pi-hole)"

    if [[ -n "$tls_directive" ]]; then
        echo ""
        info "  ${C_BOLD}One-time TLS trust (macOS)${C_RESET}:"
        printf "    ssh %s 'sudo cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt' \\\\\n" "$ssh_edge"
        printf "      > /tmp/caddy-grid-root.crt\n"
        printf "    sudo security add-trusted-cert -d -r trustRoot \\\\\n"
        printf "      -k /Library/Keychains/System.keychain /tmp/caddy-grid-root.crt\n"
    fi
}

# ── Doctor ─────────────────────────────────────────────────────────────────────

tool_doctor() {
    local ssh_edge
    ssh_edge=$(_caddy_ssh_for "edge")
    if [[ -z "$ssh_edge" ]]; then
        warn "No edge node registered."; return
    fi

    info "── caddy service (${ssh_edge})"
    _edge_ssh "$ssh_edge" \
        "systemctl --no-pager status caddy 2>&1 | head -20" \
        || warn "Could not reach edge node"
    echo ""

    info "── caddy config validate"
    _edge_ssh "$ssh_edge" \
        "sudo caddy validate --config /etc/caddy/Caddyfile 2>&1" || true
    echo ""

    info "── Pi-hole .grid DNS entries"
    _edge_ssh "$ssh_edge" \
        "grep '\.grid' /etc/pihole/custom.list 2>/dev/null || echo '  (none found)'" || true
    echo ""

    info "── upstream reachability (edge → core)"
    local core_ip
    core_ip=$(_edge_ssh "$ssh_edge" \
        "grep -oE 'reverse_proxy ([0-9.]+)' /etc/caddy/Caddyfile 2>/dev/null | head -1 | awk '{print \$2}' || true" || true)

    if [[ -n "$core_ip" ]]; then
        local checks="n8n:5678:/healthz faigate:8090:/health openclaw:18789:/health"
        for entry in $checks; do
            local svc port path
            svc="${entry%%:*}";  entry="${entry#*:}"
            port="${entry%%:*}"; path="${entry#*:}"
            _edge_ssh "$ssh_edge" \
                "curl -sf --max-time 4 http://${core_ip}:${port}${path} >/dev/null \
                 && echo '  ✔ ${svc} (${core_ip}:${port})' \
                 || echo '  ✘ ${svc} not reachable (${core_ip}:${port})'" || true
        done
    else
        warn "Could not determine core IP from Caddyfile"
    fi
    echo ""

    info "── listening ports (edge)"
    _edge_ssh "$ssh_edge" \
        "sudo ss -tlnp 2>/dev/null | grep -E ':80 |:443 ' \
         || echo '  (80/443 not listening — Caddy may be down)'" || true
}
