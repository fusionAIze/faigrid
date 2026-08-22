#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

# ==============================================================================
# log_event() — write path reaches disk as an unprivileged caller
#
# Proves that a non-root caller's event reaches BOTH grid-system.log and
# grid-events.jsonl by overriding LOG_DIR to a writable sandbox path, and
# that the sudo setup block is not re-run once the events file is writable.
# ==============================================================================

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export CORE_ROOT="${REPO_ROOT}/core"

    # Override LOG_DIR to a per-test sandbox the current (unprivileged) user
    # can write — no root, no sudo, no /var/log.
    export LOG_DIR="${BATS_TEST_TMPDIR}/log"
    mkdir -p "$LOG_DIR"

    source "${CORE_ROOT}/workbench/scripts/_lib.sh"

    # Stub sudo so any unexpected sudo call is observable (and harmless),
    # and tally every invocation for the "no re-run" assertion.
    _sudo_calls="${BATS_TEST_TMPDIR}/sudo_calls"
    : > "$_sudo_calls"
    sudo() { echo "sudo: $*" >&2; echo 1 >> "$_sudo_calls"; return 0; }
    export -f sudo
}

@test "log_event writes a valid JSONL line to both files" {
    run log_event "test" "INFO" "hello"

    [ -f "${LOG_DIR}/grid-system.log" ]
    [ -f "${LOG_DIR}/grid-events.jsonl" ]

    # Both files must contain the same single JSONL line.
    [ "$(wc -l < "${LOG_DIR}/grid-system.log" | tr -d ' ')" -eq 1 ]
    [ "$(wc -l < "${LOG_DIR}/grid-events.jsonl" | tr -d ' ')" -eq 1 ]

    # The JSON must be valid and carry the expected fields.
    run jq -e '.component == "test" and .severity == "INFO" and .message == "hello"' \
        "${LOG_DIR}/grid-system.log"
    [ "$status" -eq 0 ]

    run jq -e '.component == "test" and .severity == "INFO"' \
        "${LOG_DIR}/grid-events.jsonl"
    [ "$status" -eq 0 ]
}

@test "log_event severity fragment is present in events file" {
    log_event "test" "INFO" "hello"
    grep -q '"severity":"INFO"' "${LOG_DIR}/grid-events.jsonl"
}

@test "log_event does not re-run sudo once events file is writable" {
    log_event "test" "INFO" "first"

    local sudo_calls_before
    sudo_calls_before="$(sudo_calls_count)"
    log_event "test" "INFO" "second"
    log_event "test" "INFO" "third"
    local sudo_calls_after
    sudo_calls_after="$(sudo_calls_count)"

    # No additional sudo invocations on subsequent calls.
    [ "$sudo_calls_before" -eq "$sudo_calls_after" ]

    # All three events still landed in both files.
    [ "$(wc -l < "${LOG_DIR}/grid-events.jsonl" | tr -d ' ')" -eq 3 ]
    [ "$(wc -l < "${LOG_DIR}/grid-system.log" | tr -d ' ')" -eq 3 ]
}

@test "log_event failure path attempts sudo at most once per process" {
    # Read-only LOG_DIR that exists but the current user cannot write, plus a
    # failing sudo stub: the dir/file never become writable, so this exercises
    # the failure path where setup can never succeed.
    local readonly_dir="${BATS_TEST_TMPDIR}/readonly-log"
    mkdir -p "$readonly_dir"
    chmod 555 "$readonly_dir"

    local failed_sudo_calls="${BATS_TEST_TMPDIR}/failed_sudo_calls"
    : > "$failed_sudo_calls"
    sudo() { echo 1 >> "$failed_sudo_calls"; return 1; }
    export -f sudo

    export LOG_DIR="$readonly_dir"

    log_event "test" "ERROR" "first"
    local calls_after_first
    calls_after_first="$(failed_sudo_calls_count)"

    log_event "test" "ERROR" "second"
    log_event "test" "ERROR" "third"
    local calls_after_third
    calls_after_third="$(failed_sudo_calls_count)"

    # One setup attempt's worth of sudo (<= 5), not repeated across calls.
    [ "$calls_after_first" -le 5 ]
    [ "$calls_after_first" -eq "$calls_after_third" ]
}

sudo_calls_count() {
    if [ -f "${BATS_TEST_TMPDIR}/sudo_calls" ]; then
        wc -l < "${BATS_TEST_TMPDIR}/sudo_calls" | tr -d ' '
    else
        echo 0
    fi
}

failed_sudo_calls_count() {
    if [ -f "${BATS_TEST_TMPDIR}/failed_sudo_calls" ]; then
        wc -l < "${BATS_TEST_TMPDIR}/failed_sudo_calls" | tr -d ' '
    else
        echo 0
    fi
}
