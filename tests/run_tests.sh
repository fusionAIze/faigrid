#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Universal Test Orchestrator
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="${REPO_ROOT}/tests"
BATS_LIB_DIR="${TESTS_DIR}/.libs/bats"
BATS_EXEC="${BATS_LIB_DIR}/bin/bats"

# ── Bootstrap Bats-core ───────────────────────────────────────────────────────
if [[ ! -x "${BATS_EXEC}" ]]; then
    echo "[TEST RUNNER] Bats-core not found. Bootstrapping locally into ${BATS_LIB_DIR}..."
    rm -rf "${BATS_LIB_DIR}"
    git clone --depth 1 https://github.com/bats-core/bats-core.git "${BATS_LIB_DIR}" > /dev/null 2>&1
    
    # Bootstrap helpers
    git clone --depth 1 https://github.com/bats-core/bats-support.git "${TESTS_DIR}/.libs/bats-support" > /dev/null 2>&1 || true
    git clone --depth 1 https://github.com/bats-core/bats-assert.git "${TESTS_DIR}/.libs/bats-assert" > /dev/null 2>&1 || true
    
    echo "[TEST RUNNER] Bootstrap complete."
fi

# ── Run Options ─────────────────────────────────────────────────────────────
run_suite() {
    local suite_name=$1
    local suite_path="${TESTS_DIR}/${suite_name}"
    
    if [[ -d "$suite_path" ]]; then
        echo "=============================================================================="
        echo "Running ${suite_name} suite..."
        echo "=============================================================================="
        "${BATS_EXEC}" --timing "${suite_path}"
    else
        echo "[WARN] Suite directory not found: ${suite_path}"
    fi
}

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 {--all | --unit | --integration | --functional | --regression | --smoke}"
    exit 1
fi

case "$1" in
    --all)
        run_suite "unit"
        run_suite "integration"
        run_suite "functional"
        run_suite "regression"
        run_suite "smoke"
        ;;
    --unit)       run_suite "unit" ;;
    --integration) run_suite "integration" ;;
    --functional)  run_suite "functional" ;;
    --regression)  run_suite "regression" ;;
    --smoke)       run_suite "smoke" ;;
    *) echo "Unknown parameter $1"; exit 1 ;;
esac
