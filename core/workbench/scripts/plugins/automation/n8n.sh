#!/usr/bin/env bash
TOOL_NAME="n8n"
TOOL_CATEGORY="automation"
TOOL_DESC="n8n Workflow Automation (Core Compose)"
TOOL_TYPE="docker"
TOOL_SERVICE="grid-core-n8n"
FAIGATE_CLIENT="n8n"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"

tool_install() {
    if [[ -f "$PROJECT_DIR/core/heart/scripts/install.sh" ]]; then
        bash "$PROJECT_DIR/core/heart/scripts/install.sh"
    fi
}
tool_update() {
    if [[ -f "$PROJECT_DIR/core/heart/scripts/update.sh" ]]; then
        bash "$PROJECT_DIR/core/heart/scripts/update.sh"
    fi
}
tool_uninstall() {
    if [[ -f "$PROJECT_DIR/core/heart/scripts/uninstall.sh" ]]; then
        bash "$PROJECT_DIR/core/heart/scripts/uninstall.sh"
    fi
}
tool_status() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^grid-core-n8n"; then
        local ver
        ver=$(docker inspect grid-core-n8n --format '{{.Config.Image}}' 2>/dev/null | grep -o '[^:]*$' || echo "")
        echo "Installed (Running${ver:+ v${ver}})"
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^grid-core-n8n"; then
        echo "Installed (Stopped)"
    else
        echo "Not installed"
    fi
}

tool_doctor() {
    local env_file="/opt/faigrid/core-heart/.env"

    # ── 1. Container state ───────────────────────────────────────────────────
    info "── n8n container status"
    local n8n_state
    n8n_state=$(docker inspect grid-core-n8n --format '{{.State.Status}}' 2>/dev/null || echo "missing")
    local restart_count
    restart_count=$(docker inspect grid-core-n8n --format '{{.RestartCount}}' 2>/dev/null || echo "0")
    printf "  State: %s  (restarts: %s)\n" "$n8n_state" "$restart_count"

    # Auto-dump logs when container is crash-looping
    if [[ "$n8n_state" == "restarting" || "$restart_count" -gt 2 ]] 2>/dev/null; then
        echo ""
        warn "Container is restarting — last 30 log lines:"
        echo ""
        docker logs grid-core-n8n --tail 30 2>&1 || true
    fi
    echo ""

    # ── 2. Postgres connectivity ─────────────────────────────────────────────
    info "── postgres connectivity"
    local pg_pass=""
    [[ -f "$env_file" ]] && pg_pass=$(grep "^POSTGRES_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "")
    if [[ "$pg_pass" == "CHANGE_ME" || -z "$pg_pass" ]]; then
        warn "POSTGRES_PASSWORD is not set in ${env_file} — run: openssl rand -hex 24"
    elif docker exec grid-postgres psql -U n8n -d n8n -h 127.0.0.1 \
            -c "SELECT 1;" >/dev/null 2>&1; then
        success "postgres TCP auth OK (user n8n)"
    else
        warn "postgres TCP auth FAILED — password in ${env_file} may not match DB"
        info "Fix: docker exec grid-postgres psql -U n8n -d n8n -c \"ALTER USER n8n WITH PASSWORD '\$(grep POSTGRES_PASSWORD ${env_file} | cut -d= -f2)';\""
    fi
    echo ""

    # ── 3. Encryption key ────────────────────────────────────────────────────
    info "── n8n encryption key"
    if [[ -f "$env_file" ]]; then
        if grep -q "CHANGE_ME" "$env_file" 2>/dev/null; then
            warn "N8N_ENCRYPTION_KEY still set to CHANGE_ME in ${env_file}"
        else
            success "N8N_ENCRYPTION_KEY is set"
        fi
    else
        warn "env file not found at ${env_file}"
    fi
    echo ""

    # ── 4. Reachability ─────────────────────────────────────────────────────
    info "── n8n reachability"
    if curl -sf --max-time 5 "http://127.0.0.1:5678/healthz" >/dev/null 2>&1; then
        success "n8n responding on http://127.0.0.1:5678"
    else
        warn "n8n not reachable on port 5678"
    fi
}
