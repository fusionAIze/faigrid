#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

# ==============================================================================
# worker/lib/worker-env.sh — reusable grid-worker environment helpers
#
# Covers the generic half of the measured worker setup: absolute-path engine
# resolution, the fail-closed api-key read, the caffeinate-wrapped server argv
# (key as an environment variable, never --api-key), the HTTP health check and
# the pidfile liveness helper. Also asserts verify.sh fails when the endpoint
# does not answer.
#
# Run via: bash tests/run_tests.sh --unit
# ==============================================================================

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export WORKER_ENV_LIB="${REPO_ROOT}/worker/lib/worker-env.sh"
    export BATS_TEST_TMPDIR

    unset WORKER_API_KEY_FILE WORKER_API_KEY_VAR WORKER_MODEL_PATH \
          WORKER_BIND_ADDR WORKER_PORT WORKER_CAFFEINATE WORKER_BIN_DIRS \
          WORKER_LLAMA_SERVER_BIN WORKER_HEALTH_URL WORKER_HEALTH_TIMEOUT \
          WORKER_PIDFILE WORKER_CTX_SIZE WORKER_PARALLEL WORKER_NGL 2>/dev/null || true

    SANDBOX_BIN="${BATS_TEST_TMPDIR}/sandbox-bin"
    mkdir -p "$SANDBOX_BIN"
    printf '#!/usr/bin/env bash\necho sandbox-llama\n' > "$SANDBOX_BIN/llama-server"
    chmod +x "$SANDBOX_BIN/llama-server"
    export SANDBOX_BIN
}

# Source the library in a clean bash and call a function. If the library is
# absent the source error is suppressed and the missing function surfaces as a
# status/output mismatch on the assertions - a real assertion failure, never a
# setup abort.
_run_fn() {
    run bash -c 'source "$1" 2>/dev/null || true; shift; "$@"' _ "${WORKER_ENV_LIB}" "$@"
}

# --- C1 / absolute-path requirement ------------------------------------------

@test "C1 absolute-path: an engine off PATH resolves via WORKER_BIN_DIRS to an absolute path" {
    export WORKER_BIN_DIRS="$SANDBOX_BIN"
    _run_fn worker_llama_server_bin
    [ "$status" -eq 0 ]
    [ "$output" = "$SANDBOX_BIN/llama-server" ]
    case "$output" in
        /*) : ;;
        *) false ;;
    esac
}

@test "C1 absolute-path: WORKER_LLAMA_SERVER_BIN override wins over PATH" {
    export WORKER_LLAMA_SERVER_BIN="$SANDBOX_BIN/llama-server"
    export WORKER_BIN_DIRS="${BATS_TEST_TMPDIR}/empty"
    mkdir -p "$WORKER_BIN_DIRS"
    _run_fn worker_llama_server_bin
    [ "$status" -eq 0 ]
    [ "$output" = "$SANDBOX_BIN/llama-server" ]
}

@test "C1 absolute-path: an absent engine returns non-zero and prints nothing" {
    export WORKER_BIN_DIRS="${BATS_TEST_TMPDIR}/empty"
    mkdir -p "$WORKER_BIN_DIRS"
    _run_fn worker_llama_server_bin
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# --- C2 / api-key read fails closed ------------------------------------------

@test "C2 fail-closed: a start path exits 1 when the key file is absent" {
    export WORKER_MODEL_PATH="/models/example-model"
    export WORKER_LLAMA_SERVER_BIN="$SANDBOX_BIN/llama-server"
    export WORKER_API_KEY_FILE="${BATS_TEST_TMPDIR}/absent.env"
    run bash -c 'source "$1" 2>/dev/null || true; shift; worker_start_llama_server || exit 1' _ "${WORKER_ENV_LIB}"
    [ "$status" -eq 1 ]
    [[ "$output" == *"api-key"* ]]
}

@test "C2 fail-closed: the key file being absent returns 1 and names the file" {
    export WORKER_API_KEY_FILE="${BATS_TEST_TMPDIR}/absent.env"
    _run_fn worker_read_api_key
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "C2 fail-closed: the key missing from an existing file returns 1 and names the variable" {
    export WORKER_API_KEY_FILE="${BATS_TEST_TMPDIR}/faigrid.env"
    export WORKER_API_KEY_VAR="LLAMA_API_KEY"
    printf 'SOME_OTHER_KEY=value\n' > "$WORKER_API_KEY_FILE"
    chmod 600 "$WORKER_API_KEY_FILE"
    _run_fn worker_read_api_key
    [ "$status" -eq 1 ]
    [[ "$output" == *"LLAMA_API_KEY"* ]]
}

@test "C2 fail-closed: an empty key value returns 1" {
    export WORKER_API_KEY_FILE="${BATS_TEST_TMPDIR}/faigrid.env"
    printf 'LLAMA_API_KEY=\n' > "$WORKER_API_KEY_FILE"
    chmod 600 "$WORKER_API_KEY_FILE"
    _run_fn worker_read_api_key
    [ "$status" -eq 1 ]
}

@test "C2 fail-closed: an unset WORKER_API_KEY_FILE returns 1" {
    _run_fn worker_read_api_key
    [ "$status" -eq 1 ]
    [[ "$output" == *"WORKER_API_KEY_FILE"* ]]
}

@test "C2 positive: an existing key is read and exported without printing the value" {
    export WORKER_API_KEY_FILE="${BATS_TEST_TMPDIR}/faigrid.env"
    printf 'export LLAMA_API_KEY="test-key-1234"\n' > "$WORKER_API_KEY_FILE"
    chmod 600 "$WORKER_API_KEY_FILE"
    run bash -c 'source "$1" 2>/dev/null || true; shift; worker_read_api_key >/dev/null; printf "%s" "$LLAMA_API_KEY"' _ "${WORKER_ENV_LIB}"
    [ "$status" -eq 0 ]
    [ "$output" = "test-key-1234" ]
}

# --- C1 / caffeinate and the server argv -------------------------------------

@test "C1 caffeinate: the server command is wrapped when enabled" {
    export WORKER_LLAMA_SERVER_BIN="$SANDBOX_BIN/llama-server"
    export WORKER_MODEL_PATH="/models/example-model"
    export WORKER_CAFFEINATE=yes
    _run_fn worker_print_llama_command
    [ "$status" -eq 0 ]
    [[ "$output" == caffeinate* ]]
    [[ "$output" == *"-dimsu"* ]]
    [[ "$output" == *"--host 0.0.0.0"* ]]
}

@test "C1 caffeinate: the wrapper is omitted when disabled" {
    export WORKER_LLAMA_SERVER_BIN="$SANDBOX_BIN/llama-server"
    export WORKER_MODEL_PATH="/models/example-model"
    export WORKER_CAFFEINATE=no
    _run_fn worker_print_llama_command
    [ "$status" -eq 0 ]
    [[ "$output" != caffeinate* ]]
}

@test "C2 command: the api-key is never passed as an --api-key flag" {
    export WORKER_LLAMA_SERVER_BIN="$SANDBOX_BIN/llama-server"
    export WORKER_MODEL_PATH="/models/example-model"
    export WORKER_CAFFEINATE=yes
    _run_fn worker_print_llama_command
    [ "$status" -eq 0 ]
    [[ "$output" != *"--api-key"* ]]
}

@test "C2 command: an unset WORKER_MODEL_PATH refuses to build the command" {
    export WORKER_LLAMA_SERVER_BIN="$SANDBOX_BIN/llama-server"
    _run_fn worker_print_llama_command
    [ "$status" -eq 1 ]
    [[ "$output" == *"WORKER_MODEL_PATH"* ]]
}

# --- C2 / HTTP health check ---------------------------------------------------

@test "C2 health check: a dead endpoint returns 1 and names the endpoint" {
    export WORKER_HEALTH_URL="http://127.0.0.1:1/v1/models"
    export WORKER_HEALTH_TIMEOUT=1
    _run_fn worker_health_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"127.0.0.1:1"* ]]
}

@test "C2 health check: a live endpoint answers 0" {
    local srv port i
    srv="${BATS_TEST_TMPDIR}/srv"
    mkdir -p "$srv/v1"
    printf '{"object":"list","data":[]}' > "$srv/v1/models"
    port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"

    python3 -m http.server "$port" --bind 127.0.0.1 --directory "$srv" >/dev/null 2>&1 &
    SRV_PID=$!
    i=0
    while [ "$i" -lt 50 ]; do
        if curl -fsS "http://127.0.0.1:${port}/v1/models" >/dev/null 2>&1; then break; fi
        sleep 0.1
        i=$((i + 1))
    done

    export WORKER_HEALTH_URL="http://127.0.0.1:${port}/v1/models"
    export WORKER_HEALTH_TIMEOUT=2
    _run_fn worker_health_check
    local st="$status" out="$output"
    kill "$SRV_PID" 2>/dev/null || true
    wait "$SRV_PID" 2>/dev/null || true
    [ "$st" -eq 0 ]
    [[ "$out" == *"answered"* ]]
}

# --- C2 / service durability liveness helper ---------------------------------

@test "C2 service durability: a live pidfile reports running" {
    export WORKER_PIDFILE="${BATS_TEST_TMPDIR}/worker.pid"
    sleep 5 &
    LIVE_PID=$!
    printf '%s\n' "$LIVE_PID" > "$WORKER_PIDFILE"
    _run_fn worker_service_running
    local st="$status"
    kill "$LIVE_PID" 2>/dev/null || true
    wait "$LIVE_PID" 2>/dev/null || true
    [ "$st" -eq 0 ]
}

@test "C2 service durability: a stale pid reports not running with status 1" {
    export WORKER_PIDFILE="${BATS_TEST_TMPDIR}/worker.pid"
    printf '999999\n' > "$WORKER_PIDFILE"
    _run_fn worker_service_running
    [ "$status" -eq 1 ]
}

@test "C2 service durability: a malformed pidfile reports not running with status 1" {
    export WORKER_PIDFILE="${BATS_TEST_TMPDIR}/worker.pid"
    printf 'not-a-pid\n' > "$WORKER_PIDFILE"
    _run_fn worker_service_running
    [ "$status" -eq 1 ]
}

# --- C2 / verify.sh integration ----------------------------------------------

@test "C2 verify.sh fails when the inference endpoint does not answer" {
    export WORKER_HEALTH_URL="http://127.0.0.1:1/v1/models"
    export WORKER_HEALTH_TIMEOUT=1
    run bash "${REPO_ROOT}/worker/scripts/verify.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"127.0.0.1:1"* ]]
}
