#!/usr/bin/env bash
TOOL_NAME="antigravity"
TOOL_CATEGORY="clis"
TOOL_DESC="Antigravity AI IDE — Google"
TOOL_TYPE="apt"
# Install via Google's apt repo: https://antigravity.google/download/linux

tool_install() {
    # Add the Google signing key and repo if not already present
    if ! apt-cache show antigravity >/dev/null 2>&1; then
        curl -fsSL https://antigravity.google/linux/linux_signing_key.pub \
            | sudo gpg --dearmor -o /usr/share/keyrings/antigravity.gpg
        echo "deb [signed-by=/usr/share/keyrings/antigravity.gpg arch=amd64] \
https://antigravity.google/linux/deb/ stable main" \
            | sudo tee /etc/apt/sources.list.d/antigravity.list > /dev/null
        sudo apt-get update -qq
    fi
    sudo apt-get install -y antigravity
}
tool_update() {
    sudo apt-get install -y --only-upgrade antigravity
}
tool_status() {
    if command -v antigravity >/dev/null 2>&1; then
        local ver
        ver=$(antigravity --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}
tool_uninstall() {
    sudo apt-get remove -y antigravity
    sudo rm -f /usr/share/keyrings/antigravity.gpg \
               /etc/apt/sources.list.d/antigravity.list
}
