#!/usr/bin/env bash
TOOL_NAME="openclaw"
TOOL_CATEGORY="agents"
TOOL_DESC="Host-native OpenClaw orchestrator"
TOOL_TYPE="systemd"

tool_install() {
    echo "Please use docs/runbooks/step-02_5-openclaw-native.md to install."
}
tool_update() {
    # Would call the native update script and restart service
    sudo systemctl restart openclaw.service || true
}
tool_status() {
    if systemctl is-active --quiet openclaw.service; then
        echo "Installed (Running)"
    elif systemctl is-enabled --quiet openclaw.service 2>/dev/null; then
        echo "Installed (Stopped)"
    else
        echo "Not installed"
    fi
}
