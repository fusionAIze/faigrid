#!/usr/bin/env bash
# Plugin Template for nexus-core Workbench
# ─────────────────────────────────────────────────────────────────────────────
# TOOL_CATEGORY: clis | routers | memory | agents | automation | wrappers
# TOOL_TYPE:     npm | apt|dnf | pipx | git | binary | docker | tbd
# TOOL_MANAGED:  (omit) = user-installable  |  "auto" = hide from install/boost/update
# ─────────────────────────────────────────────────────────────────────────────

TOOL_NAME="example"
TOOL_CATEGORY="clis"
TOOL_DESC="Example descriptive text for the registry"
TOOL_TYPE="npm"

# ── Optional: OS / package-manager detection ──────────────────────────────────
# Use when the tool is distributed via system packages (apt, dnf/yum, brew).
# Copy this helper inline — plugins are sourced in isolated subshells and cannot
# rely on _lib.sh being loaded.
#
# _detect_pkg_manager() {
#     if   command -v apt-get >/dev/null 2>&1; then echo "apt"
#     elif command -v dnf     >/dev/null 2>&1; then echo "dnf"
#     elif command -v yum     >/dev/null 2>&1; then echo "yum"
#     elif command -v brew    >/dev/null 2>&1; then echo "brew"
#     else                                          echo "unknown"
#     fi
# }
#
# _install_deb() { ... }
# _install_rpm() { ... }
# _install_brew() { ... }

# ── Optional: pipx bootstrap ──────────────────────────────────────────────────
# Use when the tool is distributed via PyPI / pipx.
#
# _bootstrap_pipx() {
#     if ! command -v pipx >/dev/null 2>&1; then
#         sudo apt-get install -y pipx 2>/dev/null \
#             || sudo python3 -m pip install pipx --break-system-packages
#         export PATH="$PATH:$HOME/.local/bin"
#         pipx ensurepath 2>/dev/null || true
#     fi
# }

# ─────────────────────────────────────────────────────────────────────────────

tool_install() {
    # Single-env examples:
    #   npm:   sudo npm install -g example-cli
    #   pipx:  _bootstrap_pipx && pipx install example-cli
    #   git:   sudo git clone https://github.com/org/example /opt/fusionaize-nexus/example
    #   curl:  curl -fsSL https://example.com/install.sh | sh
    #
    # Multi-env example:
    #   local pm; pm=$(_detect_pkg_manager)
    #   case "$pm" in
    #       apt)     _install_deb ;;
    #       dnf|yum) _install_rpm ;;
    #       brew)    _install_brew ;;
    #       *) echo "Unsupported package manager. See https://example.com/install" >&2; return 1 ;;
    #   esac
    echo "Installing ${TOOL_NAME}..."
}

tool_update() {
    # npm:   sudo npm update -g example-cli
    # pipx:  pipx upgrade example-cli
    # git:   ( cd /opt/fusionaize-nexus/example && sudo git pull )
    # apt:   sudo apt-get install -y --only-upgrade example
    # dnf:   sudo dnf upgrade -y example
    echo "Updating ${TOOL_NAME}..."
}

tool_status() {
    # MUST print exactly "Not installed" when the tool is absent —
    # the registry uses this string to determine install state.
    #
    # binary/cmd:  command -v example-cli
    # pipx:        pipx list --short | awk '/^example-cli /{print $2}'
    # git hash:    git -C /opt/... rev-parse --short HEAD 2>/dev/null
    # systemctl:   systemctl is-active example.service 2>/dev/null

    if command -v example-cli >/dev/null 2>&1; then
        local ver
        ver=$(example-cli --version 2>&1 | head -1 || echo "")
        echo "Installed${ver:+ (${ver})}"
    else
        echo "Not installed"
    fi
}

tool_uninstall() {
    # npm:   sudo npm uninstall -g example-cli
    # pipx:  pipx uninstall example-cli 2>/dev/null || true
    # git:   sudo rm -rf /opt/fusionaize-nexus/example
    # apt:   sudo apt-get remove -y example && sudo rm -f /etc/apt/sources.list.d/example.list
    # dnf:   sudo dnf remove -y example && sudo rm -f /etc/yum.repos.d/example.repo
    echo "Uninstalling ${TOOL_NAME}..."
}

# ── Optional: interactive configuration ───────────────────────────────────────
# Called from the Workbench "Configure" menu (option 5).
# _lib.sh is sourced before this plugin in the subshell, so nexus_write_env,
# nexus_read_env, nexus_mask, nexus_ensure_sourced, info, success, warn are
# all available here.
#
# API-key pattern (most CLI tools):
#
# tool_configure() {
#     local current
#     current=$(nexus_read_env "EXAMPLE_API_KEY")
#     printf "  EXAMPLE_API_KEY [%s]: " "$(nexus_mask "$current")"
#     read -r -s api_key; echo ""
#     [[ -z "$api_key" && -n "$current" ]] && { info "Kept existing key."; return 0; }
#     [[ -z "$api_key" ]] && { warn "No key provided. Skipping."; return 0; }
#     nexus_write_env "EXAMPLE_API_KEY" "$api_key"
#     nexus_ensure_sourced
#     success "EXAMPLE_API_KEY saved to ~/.config/nexus/nexus.env"
# }
