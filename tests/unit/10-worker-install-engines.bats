#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

# ==============================================================================
# worker/scripts/install.sh — engine recognition tests (dry-run)
#
# Tests that install.sh recognises llama.cpp as a first-class worker engine
# alongside Ollama and LM Studio, names its tunnel port, states the 8GB
# guidance for llama.cpp in its own terms, and warns when none of the three
# engines are present.
# ==============================================================================

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export BATS_TEST_TMPDIR

    SANDBOX_BIN="${BATS_TEST_TMPDIR}/sandbox-bin"
    mkdir -p "$SANDBOX_BIN"

    cat > "$SANDBOX_BIN/uname" << 'SCRIPT'
#!/usr/bin/env bash
case "$1" in
    -s) echo "Darwin" ;;
    -m) echo "arm64" ;;
    *) /usr/bin/uname "$@" ;;
esac
SCRIPT
    chmod +x "$SANDBOX_BIN/uname"
}

@test "C1 - install.sh recognises llama.cpp alongside Ollama and LM Studio" {
    run env PATH="${SANDBOX_BIN}:${PATH}" bash "${REPO_ROOT}/worker/scripts/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"llama.cpp"* ]]
}

@test "C1 - install.sh names the llama.cpp tunnel port (8080) alongside the other two" {
    run env PATH="${SANDBOX_BIN}:${PATH}" bash "${REPO_ROOT}/worker/scripts/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"For llama.cpp:"* ]]
    [[ "$output" == *"8080"* ]]
}

@test "C2 - 8GB guidance states --ctx-size 4096 for llama.cpp rather than only num_ctx for Ollama" {
    run env PATH="${SANDBOX_BIN}:${PATH}" bash "${REPO_ROOT}/worker/scripts/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--ctx-size 4096"* ]]
}

@test "C3 - worker with none of the three engines present is told so by name" {
    run env PATH="${SANDBOX_BIN}:${PATH}" bash "${REPO_ROOT}/worker/scripts/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No inference engine detected"* ]]
    [[ "$output" == *"Ollama"* ]]
    [[ "$output" == *"LM Studio"* ]]
    [[ "$output" == *"llama.cpp"* ]]
}
