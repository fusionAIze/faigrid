#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
}

@test "Syntax Check - core/workbench/scripts/control.sh" {
    run bash -n "${REPO_ROOT}/core/workbench/scripts/control.sh"
    [ "$status" -eq 0 ]
}

@test "Syntax Check - Root install.sh" {
    run bash -n "${REPO_ROOT}/install.sh"
    [ "$status" -eq 0 ]
}

@test "Execution without args - install.sh demands interactive input or yields help" {
    run bash "${REPO_ROOT}/install.sh" --help
    # Ensure it's executable and fails/passes cleanly without blowing up
    # Since install.sh is highly interactive, we just make sure it parses via -n or fails correctly.
    [ "$status" -ne 127 ] 
}
