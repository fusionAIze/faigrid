#!/usr/bin/env bash
# Plugin Template for nexus-core Workbench

# Set the metadata describing this tool. 
# TOOL_CATEGORY should be one of: clis, routers, memory, agents, automation, wrappers
TOOL_NAME="example"
TOOL_CATEGORY="clis"
TOOL_DESC="Example descriptive text for the registry"
TOOL_TYPE="pipx" # e.g., pipx, npm, git, docker

tool_install() {
    # Place your installation commands here. Examples:
    # pipx install example-cli
    # npm install -g example-cli
    echo "Installing ${TOOL_NAME}..."
}

tool_update() {
    # Place your update commands here. Examples:
    # pipx upgrade example-cli
    # npm update -g example-cli
    echo "Updating ${TOOL_NAME}..."
}

tool_status() {
    # Check if the tool is installed and return its status/version.
    # MUST print "Not installed" if it is missing.
    #
    # Example for pipx:
    # pipx list --short | grep "^example-cli" || echo "Not installed"
    
    if command -v example-cli >/dev/null 2>&1; then
        echo "Installed ($(example-cli --version))"
    else
        echo "Not installed"
    fi
}
