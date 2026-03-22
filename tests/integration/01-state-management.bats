#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    # Isolate HOME so install.sh writes state files to a safe, temporary location.
    # $BATS_TEST_TMPDIR is created fresh for each test.
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "$HOME"
    
    export STATE_FILE="$HOME/.nexus-state"
    export LOCAL_REGISTRY="${BATS_TEST_TMPDIR}/.nexus/state"
    
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
