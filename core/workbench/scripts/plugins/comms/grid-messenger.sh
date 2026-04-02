#!/usr/bin/env bash
TOOL_NAME="grid-messenger"
TOOL_CATEGORY="comms"
TOOL_DESC="Telegram bridge — approvals & notifications for grid-core"
TOOL_TYPE="systemd"
TOOL_SERVICE="grid-messenger"
TOOL_UPDATE_TYPE="git"
INSTALL_DIR="/opt/grid-messenger"

# Resolve messenger source relative to this plugin file
_GM_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_GM_SRC="$(cd "${_GM_HERE}/../../../../messenger" 2>/dev/null && pwd)" || _GM_SRC=""

_CONFIG_DIR="/etc/grid-messenger"
_CONFIG_FILE="${_CONFIG_DIR}/config.env"

# ── Lifecycle ──────────────────────────────────────────────────────────────────

tool_install() {
    if [[ -z "$_GM_SRC" || ! -f "${_GM_SRC}/install.sh" ]]; then
        warn "install.sh not found at ${_GM_SRC}/install.sh"
        return 1
    fi
    sudo bash "${_GM_SRC}/install.sh"
    success "grid-messenger installed. Run Configure (5) to set Telegram token and allowed users."
}

tool_update() {
    if [[ -z "$_GM_SRC" || ! -f "${_GM_SRC}/update.sh" ]]; then
        warn "update.sh not found — restarting service only."
        sudo systemctl restart grid-messenger.service 2>/dev/null || true
        return 0
    fi
    sudo bash "${_GM_SRC}/update.sh"
}

tool_status() {
    if systemctl is-active --quiet grid-messenger.service 2>/dev/null; then
        local pending
        pending=$(curl -sf --max-time 2 "http://127.0.0.1:${WEBHOOK_PORT:-9119}/health" \
            2>/dev/null | grep -o '"pending_approvals":[0-9]*' | cut -d: -f2 || echo "")
        echo "Installed (Running${pending:+ — ${pending} pending})"
    elif systemctl is-enabled --quiet grid-messenger.service 2>/dev/null; then
        echo "Installed (Stopped)"
    else
        echo "Not installed"
    fi
}

tool_uninstall() {
    warn "This will stop and disable grid-messenger."
    printf "  Proceed? (y/N): "; read -r confirm
    [[ "${confirm:-N}" =~ ^[Yy]$ ]] || { info "Aborted."; return 0; }
    sudo systemctl stop    grid-messenger.service 2>/dev/null || true
    sudo systemctl disable grid-messenger.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/grid-messenger.service
    sudo systemctl daemon-reload
    warn "Files at ${INSTALL_DIR} and ${_CONFIG_DIR} retained. Remove manually if needed."
    success "grid-messenger disabled."
}

# ── Configure ──────────────────────────────────────────────────────────────────

tool_configure() {
    info "── grid-messenger configuration"
    printf "  ${C_DIM}Config: %s${C_RESET}\n\n" "$_CONFIG_FILE"

    if ! sudo test -f "$_CONFIG_FILE" 2>/dev/null; then
        warn "Config not found. Run Install first."
        return 1
    fi

    # Helper: read current value from config.env
    _gm_cur() {
        sudo grep "^${1}=" "$_CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 || echo ""
    }
    # Helper: write/update a key in config.env
    _gm_set() {
        local key="$1" val="$2" tmp
        tmp=$(mktemp)
        sudo grep -v "^${key}=" "$_CONFIG_FILE" > "$tmp" 2>/dev/null || true
        printf '%s=%s\n' "$key" "$val" >> "$tmp"
        sudo mv "$tmp" "$_CONFIG_FILE"
        sudo chown root:grid-messenger "$_CONFIG_FILE" 2>/dev/null || true
        sudo chmod 640 "$_CONFIG_FILE" 2>/dev/null || true
    }

    # ── Telegram Bot Token ────────────────────────────────────────────────────
    info "── Telegram"
    local cur_token
    cur_token=$(_gm_cur "TELEGRAM_BOT_TOKEN")
    if [[ -n "$cur_token" ]]; then
        printf "  Bot token         [%s]: " "$(grid_mask "$cur_token")"
    else
        printf "  Bot token         [(not set) — get from @BotFather]: "
    fi
    read -r -s token; echo ""
    [[ -n "$token" ]] && _gm_set "TELEGRAM_BOT_TOKEN" "$token"

    # ── Allowed User IDs ──────────────────────────────────────────────────────
    local cur_ids
    cur_ids=$(_gm_cur "TELEGRAM_ALLOWED_USER_IDS")
    printf "  Allowed user IDs  [%s]: " "${cur_ids:-(not set) — get from @userinfobot}"
    read -r input_ids
    if [[ -n "$input_ids" ]]; then
        _gm_set "TELEGRAM_ALLOWED_USER_IDS" "$input_ids"
        # Default NOTIFY_CHAT_IDS to same value if not already set
        local cur_notify
        cur_notify=$(_gm_cur "NOTIFY_CHAT_IDS")
        [[ -z "$cur_notify" ]] && _gm_set "NOTIFY_CHAT_IDS" "$input_ids"
    fi

    # ── Notification Chat IDs ─────────────────────────────────────────────────
    local cur_notify
    cur_notify=$(_gm_cur "NOTIFY_CHAT_IDS")
    printf "  Notify chat IDs   [%s]: " "${cur_notify:-(defaults to allowed user IDs)}"
    read -r input_notify
    [[ -n "$input_notify" ]] && _gm_set "NOTIFY_CHAT_IDS" "$input_notify"

    echo ""
    info "── Service URLs (defaults fine for local core)"
    local cur_n8n; cur_n8n=$(_gm_cur "N8N_BASE_URL")
    printf "  N8N_BASE_URL      [%s]: " "${cur_n8n:-http://127.0.0.1:5678}"
    read -r v; [[ -n "$v" ]] && _gm_set "N8N_BASE_URL" "$v"

    local cur_fg; cur_fg=$(_gm_cur "FAIGATE_URL")
    printf "  FAIGATE_URL       [%s]: " "${cur_fg:-http://127.0.0.1:8090}"
    read -r v; [[ -n "$v" ]] && _gm_set "FAIGATE_URL" "$v"

    local cur_oc; cur_oc=$(_gm_cur "OPENCLAW_URL")
    printf "  OPENCLAW_URL      [%s]: " "${cur_oc:-http://127.0.0.1:18789}"
    read -r v; [[ -n "$v" ]] && _gm_set "OPENCLAW_URL" "$v"

    echo ""
    printf "  Restart grid-messenger to apply? (Y/n): "; read -r do_restart
    if [[ ! "${do_restart:-Y}" =~ ^[Nn]$ ]]; then
        sudo systemctl restart grid-messenger.service
        sleep 2
        if systemctl is-active --quiet grid-messenger.service; then
            success "grid-messenger running."
        else
            warn "Service failed to start — check: sudo journalctl -u grid-messenger -n 30"
        fi
    fi

    echo ""
    info "  n8n → grid-messenger: POST http://127.0.0.1:9119/approval/request"
    info "  n8n → notifications:  POST http://127.0.0.1:9119/notify"
    info "  Health:               GET  http://127.0.0.1:9119/health"
}

# ── Doctor ─────────────────────────────────────────────────────────────────────

tool_doctor() {
    local port="${WEBHOOK_PORT:-9119}"

    info "── grid-messenger service"
    systemctl --no-pager status grid-messenger.service 2>&1 | head -20 || true
    echo ""

    info "── config file"
    if sudo test -f "$_CONFIG_FILE" 2>/dev/null; then
        local token ids
        token=$(sudo grep "^TELEGRAM_BOT_TOKEN=" "$_CONFIG_FILE" 2>/dev/null \
            | cut -d'=' -f2 || echo "")
        ids=$(sudo grep "^TELEGRAM_ALLOWED_USER_IDS=" "$_CONFIG_FILE" 2>/dev/null \
            | cut -d'=' -f2 || echo "")
        if [[ -z "$token" ]]; then
            warn "TELEGRAM_BOT_TOKEN not set — run Configure"
        else
            success "TELEGRAM_BOT_TOKEN set (${token:0:8}…)"
        fi
        if [[ -z "$ids" ]]; then
            warn "TELEGRAM_ALLOWED_USER_IDS not set — bot will block all users"
        else
            success "Allowed user IDs: ${ids}"
        fi
    else
        warn "Config file not found at ${_CONFIG_FILE} — run Install"
    fi
    echo ""

    info "── HTTP webhook server (:${port})"
    local health
    health=$(curl -sf --max-time 3 "http://127.0.0.1:${port}/health" 2>/dev/null || echo "")
    if [[ -n "$health" ]]; then
        success "HTTP server responding"
        echo "  $health"
    else
        warn "HTTP server not reachable on port ${port}"
    fi
    echo ""

    info "── recent logs"
    sudo journalctl -u grid-messenger.service --no-pager -n 20 2>/dev/null \
        | grep -v "^--" || true
}
