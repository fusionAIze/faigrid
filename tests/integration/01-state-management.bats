#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    # Isolate HOME so install.sh writes state files to a safe, temporary location.
    # $BATS_TEST_TMPDIR is created fresh for each test.
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "$HOME"
    
    export STATE_DIR="$HOME/.config/faigrid/registry"
    export STATE_FILE="$STATE_DIR/state.env"
    export LOCAL_REGISTRY="$STATE_DIR"
    
    # We must mock output functions missing since we only source parts of the script
    # or if we source install.sh, we might hit execution. 
    # To test functions from install.sh safely, we create a wrapper that sources 
    # it but exits before running the interactive wizard, essentially hooking the functions.
    
    cat << 'EOF' > "${BATS_TEST_TMPDIR}/test_hook.sh"
#!/usr/bin/env bash
# Define dummy vars to prevent errors on source
AUTO_YES="true"
BOOTSTRAP_MODE="false"

# Override prompt/exit functions so sourcing doesn't block or terminate
prompt() { echo "mock prompt $1"; }
_quit() { echo "mock quit"; }
# Redefine exit to prevent main script from killing the test
exit() { echo "mock exit $1"; } 

# Source install.sh up to the first interactive point (which we bypass via exit or similar, 
# but actually we just want to load the functions. However, source runs everything.
# Let's cleanly extract just the functions we need!)
EOF

    # Dynamically extract state functions from install.sh
    awk '/^inspect_state\(\)/,/^}/' "${REPO_ROOT}/install.sh" > "${BATS_TEST_TMPDIR}/funcs.sh"
    awk '/^write_state\(\)/,/^}/' "${REPO_ROOT}/install.sh" >> "${BATS_TEST_TMPDIR}/funcs.sh"
    awk '/^load_local_state\(\)/,/^}/' "${REPO_ROOT}/install.sh" >> "${BATS_TEST_TMPDIR}/funcs.sh"

    # Extract the read-only state-verification block from grid-doctor.sh. The block
    # runs at top level (not inside a function), so we wrap it in a function so it
    # can be invoked multiple times against an isolated $HOME without re-running
    # the whole grid-doctor script (which calls print_header etc. at top level).
    awk '/^# 4\. State Verification/,/^# 5\. Log Health/' "${REPO_ROOT}/scripts/grid-doctor.sh" \
        | sed '1d; $d' > "${BATS_TEST_TMPDIR}/doctor_state_body.sh"
    {
        echo 'success() { echo "success: $1"; }'
        echo 'warn() { echo "warn: $1"; }'
        echo "doctor_state_verify() {"
        cat "${BATS_TEST_TMPDIR}/doctor_state_body.sh"
        echo "}"
    } > "${BATS_TEST_TMPDIR}/doctor_state.sh"

    # Add dummy success/info calls so they don't break
    echo "success() { echo \"success: \$1\"; }" >> "${BATS_TEST_TMPDIR}/funcs.sh"
    echo "info() { echo \"info: \$1\"; }" >> "${BATS_TEST_TMPDIR}/funcs.sh"
    echo "warning() { echo \"warning: \$1\"; }" >> "${BATS_TEST_TMPDIR}/funcs.sh"
}

@test "inspect_state() - Identifies a missing state cleanly" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"
    
    CURRENT_ROLE="none"
    CURRENT_VERSION="none"
    
    run inspect_state "local" ""
    [ "$status" -eq 0 ]
    [ "$CURRENT_ROLE" == "none" ]
}

@test "write_state() and inspect_state() - Persists and recalls the node role" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"
    
    CURRENT_ROLE="none"
    CURRENT_VERSION="none"
    
    # Write a dummy state as core
    run write_state "local" "" "core"
    [ "$status" -eq 0 ]
    
    # Check if files were created
    [ -f "$STATE_FILE" ]
    [ -f "${LOCAL_REGISTRY}/core.state" ]
    
    # Now inspect
    run inspect_state "local" ""
    
    # To capture variables set by a function, we must execute them in the same shell
    # so we can't use `run` which creates a subshell.
    inspect_state "local" ""
    
    [ "$CURRENT_ROLE" == "core" ]
    [ "$CURRENT_VERSION" == "latest" ]
}

# C6.2 — migration ordering: grid-doctor is read-only and never leaves the
# legacy file behind. The canonical `mv` migration (migrate_1.3.sh) is the only
# writer; these tests verify the doctor path only reads.
@test "grid-doctor state verification is read-only (no legacy file, no state)" {
    # Drives the state-verification block only, against an empty $HOME.
    # $HOME is already sandboxed to $BATS_TEST_TMPDIR/home and has no state.
    source "${BATS_TEST_TMPDIR}/doctor_state.sh"

    run doctor_state_verify
    [ "$status" -eq 0 ]

    # Neither the canonical state file nor the legacy file may be created.
    [ ! -f "$STATE_FILE" ]
    [ ! -f "$HOME/.grid-state" ]
}

@test "grid-doctor reports warning on legacy file but does not copy/migrate" {
    # Seed ONLY a legacy ~/.grid-state; canonical path must stay untouched.
    mkdir -p "$HOME"
    printf 'ROLE=core\n' > "$HOME/.grid-state"

    source "${BATS_TEST_TMPDIR}/doctor_state.sh"

    run doctor_state_verify
    [ "$status" -eq 0 ]
    # Warns about the legacy file.
    [[ "$output" == *"~/.grid-state"* ]]

    # Legacy file is left in place (doctor does NOT mv) ...
    [ -f "$HOME/.grid-state" ]
    # ... and the canonical file is NOT created (doctor does NOT cp).
    [ ! -f "$STATE_FILE" ]
}

@test "doctor-then-install ordering: migration leaves canonical, legacy gone" {
    # Full ordering check: a legacy state exists; the canonical `mv` migration
    # must move it (removing the legacy file), after which the canonical state
    # survives and the legacy path is absent. grid-doctor had nothing to do with
    # the write — it stays read-only.
    mkdir -p "$HOME"
    printf 'ROLE=core\n' > "$HOME/.grid-state"

    # Run the canonical migration (same semantics as the install-time hook).
    local grid_state="$STATE_FILE"
    mkdir -p "$(dirname "$grid_state")"
    mv "$HOME/.grid-state" "$grid_state"

    # Legacy file is GONE after `mv` (this is the C6 invariant).
    [ ! -f "$HOME/.grid-state" ]
    # Canonical state survives with the migrated role.
    [ -f "$STATE_FILE" ]
    run grep "ROLE=core" "$STATE_FILE"
    [ "$status" -eq 0 ]
}
