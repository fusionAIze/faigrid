#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export CORE_ROOT="${REPO_ROOT}/core"
    
    # Isolate HOME to protect real `~/.config/nexus/nexus.env`
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "$HOME"
}

@test "Workbench Lib - Writing and reading API keys locally" {
    source "${CORE_ROOT}/workbench/scripts/_lib.sh"
    
    # File should not exist initially
    [ ! -f "$_NEXUS_ENV_FILE" ]
    
    # Write key
    nexus_write_env "TEST_API_KEY" "sk-abc-12345"
    
    # File should now exist with correct permissions
    [ -f "$_NEXUS_ENV_FILE" ]
    local perms
    perms=$(stat -c "%a" "$_NEXUS_ENV_FILE" 2>/dev/null || stat -f "%A" "$_NEXUS_ENV_FILE" 2>/dev/null || stat -f "%Lp" "$_NEXUS_ENV_FILE" 2>/dev/null)
    [[ "$perms" == *"600"* ]]
    
    # Read key
    local result
    result=$(nexus_read_env "TEST_API_KEY")
    [ "$result" == "sk-abc-12345" ]
    
    # Update key
    nexus_write_env "TEST_API_KEY" "sk-xyz-99999"
    result=$(nexus_read_env "TEST_API_KEY")
    [ "$result" == "sk-xyz-99999" ]
}

@test "Workbench Lib - Ensures .bashrc is only hooked once" {
    source "${CORE_ROOT}/workbench/scripts/_lib.sh"
    
    # Create empty mock bashrc
    touch "${HOME}/.bashrc"
    
    nexus_ensure_sourced
    nexus_ensure_sourced
    
    local count
    count=$(grep -c "nexus/nexus.env" "${HOME}/.bashrc" || echo 0)
    [ "$count" -eq 1 ] # 1 matching line containing the path twice
}
