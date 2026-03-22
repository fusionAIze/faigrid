#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export CORE_ROOT="${REPO_ROOT}/core"
}

@test "Workbench Lib - UI color variables exist" {
    source "${CORE_ROOT}/workbench/scripts/_lib.sh"
    [ -n "$C_RESET" ]
    [ -n "$C_GREEN" ]
    [ -n "$C_MAGENTA" ]
}

@test "Workbench Lib - info() outputs correctly formatted cyan text" {
    source "${CORE_ROOT}/workbench/scripts/_lib.sh"
    run info "Test Message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO]"*"Test Message"* ]]
}

@test "Workbench Lib - nexus_mask() hides secrets securely" {
    source "${CORE_ROOT}/workbench/scripts/_lib.sh"
    
    run nexus_mask "shrtkey"
    [ "$status" -eq 0 ]
    [ "$output" == "****" ] # less than 8 chars is fully masked

    run nexus_mask "sk-antsk01-XXXXXXXXXXXXXXXXXXX"
    [ "$status" -eq 0 ]
    [ "$output" == "sk-a****" ]
}
