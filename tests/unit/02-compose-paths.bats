#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    # Mocking standard CORE_ROOT context
    export CORE_ROOT="${BATS_TEST_TMPDIR}/core"
    mkdir -p "${CORE_ROOT}/heart/compose"
    touch "${CORE_ROOT}/heart/compose/.env"
    
    # We need the real _lib.sh but executed in the isolated CORE_ROOT
    cp "${REPO_ROOT}/core/heart/scripts/_lib.sh" "${BATS_TEST_TMPDIR}/_lib.sh"
}

@test "Compose Paths - resolve_compose_paths() defaults appropriately" {
    source "${BATS_TEST_TMPDIR}/_lib.sh"
    
    # Scenario 1: Standard /opt/fusionaize-nexus path doesn't exist, fallback to repo CORE_ROOT
    run resolve_compose_paths
    
    # We must actually check variables in the current shell, not subshell.
    resolve_compose_paths
    
    [ "$STACK_DIR" == "${CORE_ROOT}/heart" ]
    [ "$COMPOSE_DIR" == "${CORE_ROOT}/heart/compose" ]
    [ "$ENV_FILE" == "${CORE_ROOT}/heart/compose/.env" ]
}

@test "Compose Paths - detects legacy compose.yml in STACK_DIR" {
    source "${BATS_TEST_TMPDIR}/_lib.sh"
    
    # Clear the subfolder and put compose.yml at root of heart
    rm -rf "${CORE_ROOT}/heart/compose"
    touch "${CORE_ROOT}/heart/compose.yml"
    
    resolve_compose_paths
    
    # It should collapse COMPOSE_DIR back to STACK_DIR if compose/ is missing but compose.yml exists
    [ "$COMPOSE_DIR" == "${CORE_ROOT}/heart" ]
}
