#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

# ==============================================================================
# install.sh — state-transition tests (dry-run / non-destructive)
#
# These tests never execute the interactive wizard or any install/deploy path.
# They either (a) drive the pure state functions extracted from install.sh with
# a sandboxed HOME, or (b) assert on `--help` / flag parsing via a throwaway
# subprocess. Nothing writes to the real ~/.config.
# ==============================================================================

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export BATS_TEST_TMPDIR

    # Isolate HOME so the canonical registry path points into the sandbox.
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "$HOME"

    # Canonical state dir/state file, mirroring install.sh's own definition.
    export STATE_DIR="${HOME}/.config/faigrid/registry"
    export STATE_FILE="${STATE_DIR}/state.env"
    export LOCAL_REGISTRY="${STATE_DIR}"

    # Extract the pure state functions from install.sh without executing it.
    awk '/^inspect_state\(\)/,/^}/'      "${REPO_ROOT}/install.sh" > "${BATS_TEST_TMPDIR}/funcs.sh"
    awk '/^write_state\(\)/,/^}/'        "${REPO_ROOT}/install.sh" >> "${BATS_TEST_TMPDIR}/funcs.sh"
    awk '/^resolve_role_dir\(\)/,/^}/'   "${REPO_ROOT}/install.sh" >> "${BATS_TEST_TMPDIR}/funcs.sh"

    # Lightweight helpers referenced by these functions.
    cat >> "${BATS_TEST_TMPDIR}/funcs.sh" << 'EOF'
success() { echo "success: $1"; }
info() { echo "info: $1"; }
warning() { echo "warning: $1"; }
EOF
}

@test "State - Missing state is detected cleanly (inspect_state)" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"

    # install.sh seeds CURRENT_ROLE/CURRENT_VERSION to "none" before calling
    # inspect_state; with no state.env present, inspect_state leaves them as-is.
    CURRENT_ROLE="none"
    CURRENT_VERSION="none"

    inspect_state "local" ""

    [ "$CURRENT_ROLE" == "none" ]
    [ "$CURRENT_VERSION" == "none" ]
}

@test "State - write_state persists role/version to canonical state.env" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"

    write_state "local" "" "core"

    [ -f "${STATE_DIR}/state.env" ]
    grep -q 'GRID_ROLE=core' "${STATE_DIR}/state.env"
    grep -q 'GRID_VERSION=latest' "${STATE_DIR}/state.env"
}

@test "State - Local registry records a per-role state file" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"

    write_state "local" "" "edge"

    [ -f "${STATE_DIR}/edge.state" ]
    grep -q 'GRID_ROLE=edge' "${STATE_DIR}/edge.state"
}

@test "State - inspect_state recalls the persisted role/version" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"

    write_state "local" "" "worker"
    CURRENT_ROLE="none"
    CURRENT_VERSION="none"

    inspect_state "local" ""

    [ "$CURRENT_ROLE" == "worker" ]
    [ "$CURRENT_VERSION" == "latest" ]
}

@test "State - role transition is reflected (worker -> core)" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"

    write_state "local" "" "worker"
    inspect_state "local" ""
    [ "$CURRENT_ROLE" == "worker" ]

    # Re-provision the same target with a different role.
    write_state "local" "" "core"
    inspect_state "local" ""
    [ "$CURRENT_ROLE" == "core" ]
    grep -q 'GRID_ROLE=core' "${STATE_DIR}/state.env"
}

@test "Role - resolve_role_dir maps documented roles to dirs" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"

    [ "$(resolve_role_dir core)" == "core/heart" ]
    [ "$(resolve_role_dir edge)" == "edge/pi" ]
    [ "$(resolve_role_dir worker)" == "worker" ]
    [ "$(resolve_role_dir backup)" == "backup" ]
    [ "$(resolve_role_dir external)" == "external" ]
    [ "$(resolve_role_dir runner)" == "core/runners" ]
}

@test "VERSION - VERSION file and install.sh agree on version" {
    local file_ver script_ver
    file_ver="$(cat "${REPO_ROOT}/VERSION")"
    script_ver="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "${REPO_ROOT}/install.sh" | head -1)"

    [ -n "$file_ver" ]
    [ "$file_ver" == "$script_ver" ]
}

@test "CLI - --help prints usage and exits 0" {
    run bash "${REPO_ROOT}/install.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "CLI - --yes and --force are parsed as flags (arg scan)" {
    # Install.sh parses --yes/--force into AUTO_YES/FORCE. We assert the flags
    # are recognized by scanning the flag-handling case block rather than
    # executing the (interactive, destructive) script.
    grep -q -- '--yes' "${REPO_ROOT}/install.sh"
    grep -q -- '--force' "${REPO_ROOT}/install.sh"

    local yes_value force_value
    yes_value=$(grep -E -- '--yes\).*AUTO_YES' "${REPO_ROOT}/install.sh" | grep -oE 'AUTO_YES="[a-z]+"')
    force_value=$(grep -E -- '--force\).*FORCE' "${REPO_ROOT}/install.sh" | grep -oE 'FORCE="[a-z]+"')

    [ "$yes_value" == 'AUTO_YES="true"' ]
    [ "$force_value" == 'FORCE="true"' ]
}

@test "CLI - unknown parameter is rejected (error path)" {
    run bash "${REPO_ROOT}/install.sh" --definitely-not-a-flag
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown parameter passed"* ]]
}

@test "Install.sh - declares the canonical registry state.env path" {
    grep -q 'STATE_DIR="${HOME}/.config/faigrid/registry"' "${REPO_ROOT}/install.sh"
    grep -q 'STATE_FILE="${STATE_DIR}/state.env"' "${REPO_ROOT}/install.sh"
}
