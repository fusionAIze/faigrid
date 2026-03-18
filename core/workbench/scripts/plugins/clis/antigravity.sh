#!/usr/bin/env bash
TOOL_NAME="antigravity"
TOOL_CATEGORY="clis"
TOOL_DESC="Antigravity AI IDE — Google"
TOOL_TYPE="apt"
# Install via Google Artifact Registry: https://antigravity.google/download/linux

tool_install() {
    # Add keyring and repo if not already present
    if ! apt-cache show antigravity >/dev/null 2>&1; then
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg \
            | sudo gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg
        echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] \
https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ \
antigravity-debian main" \
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
    sudo rm -f /etc/apt/keyrings/antigravity-repo-key.gpg \
               /etc/apt/sources.list.d/antigravity.list
}
