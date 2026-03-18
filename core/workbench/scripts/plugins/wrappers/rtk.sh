#!/usr/bin/env bash
TOOL_NAME="rtk"
TOOL_CATEGORY="wrappers"
TOOL_DESC="RTK Shell Wrapper"
TOOL_TYPE="binary"

# Official install puts the binary at ~/.local/bin/rtk
BINARY_PATH="${HOME}/.local/bin/rtk"

tool_install() {
    curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
    # Ensure ~/.local/bin is on PATH for the current session
    export PATH="$PATH:${HOME}/.local/bin"
}

tool_update() {
    # Re-running the install script pulls the latest release
    curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
}

tool_status() {
    if command -v rtk >/dev/null 2>&1 || [[ -x "${BINARY_PATH}" ]]; then
        local ver
        ver=$(rtk --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}

tool_uninstall() {
    rm -f "${BINARY_PATH}"
}
