#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export CORE_ROOT="${REPO_ROOT}/core"
    
    # Isolate HOME to protect real `~/.config/faigrid/grid.env`
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "$HOME"
}

@test "Workbench Lib - Writing and reading API keys locally" {
    source "${CORE_ROOT}/workbench/scripts/_lib.sh"
    
    # File should not exist initially
    [ ! -f "$_GRID_ENV_FILE" ]
    
    # Write key
    grid_write_env "TEST_API_KEY" "sk-abc-12345"
    
    # File should now exist with correct permissions
    [ -f "$_GRID_ENV_FILE" ]
    local perms
    perms=$(stat -c "%a" "$_GRID_ENV_FILE" 2>/dev/null || stat -f "%A" "$_GRID_ENV_FILE" 2>/dev/null || stat -f "%Lp" "$_GRID_ENV_FILE" 2>/dev/null)
    [[ "$perms" == *"600"* ]]
    
    # Read key
    local result
    result=$(grid_read_env "TEST_API_KEY")
    [ "$result" == "sk-abc-12345" ]
    
    # Update key
    grid_write_env "TEST_API_KEY" "sk-xyz-99999"
    result=$(grid_read_env "TEST_API_KEY")
    [ "$result" == "sk-xyz-99999" ]
}

@test "Workbench Lib - Ensures .bashrc is only hooked once" {
    source "${CORE_ROOT}/workbench/scripts/_lib.sh"
    
    # Create empty mock bashrc
    touch "${HOME}/.bashrc"
    
    grid_ensure_sourced
    grid_ensure_sourced
    
    local count
    count=$(grep -c "faigrid/grid.env" "${HOME}/.bashrc" || true)
    # If grep -c returns nothing, fallback to 0 safely
    if [[ -z "$count" ]]; then count=0; fi
    [ "$count" -eq 1 ] # 1 matching line containing the path twice
}
