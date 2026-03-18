#!/usr/bin/env bash
TOOL_NAME="antigravity"
TOOL_CATEGORY="clis"
TOOL_DESC="Antigravity AI IDE — Google"
TOOL_TYPE="apt|dnf"
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
