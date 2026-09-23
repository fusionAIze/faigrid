#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

# ==============================================================================
# log_event() — the write path goes through sudo (model (b), FAI-209)
#
# /var/log/faigrid is 750 root:adm and its files are 640 root:adm, so those
# modes grant read but never write. A non-root caller reaches disk only through
# sudo. These cases prove:
#   1. with sudo working, one call lands in BOTH files, via sudo;
#   2. with sudo failing, the failure is NAMED on stderr, never discarded;
#   3. C3.3 survives: the setup guard runs once per process while the writes
#      stay a separate path (one write per call).
#
# sudo is stubbed. LOG_SETUP_ATTEMPTED is process state, so each test starts
# from a fresh `source` of _lib.sh.
# ==============================================================================

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export CORE_ROOT="${REPO_ROOT}/core"

    # Override LOG_DIR to a per-test sandbox the current (unprivileged) user
    # can write, so the stubbed sudo's `tee -a` lands exactly as it would on a
    # real host where LOG_DIR is root:adm.
    export LOG_DIR="${BATS_TEST_TMPDIR}/log"
    mkdir -p "$LOG_DIR"

    source "${CORE_ROOT}/workbench/scripts/_lib.sh"

    # sudo stub: tally the invocation, then run the command as the current
    # (unprivileged) user.
    export _sudo_calls="${BATS_TEST_TMPDIR}/sudo_calls"
    : > "$_sudo_calls"
    sudo() { echo "$*" >> "$_sudo_calls"; "$@"; }
    export -f sudo
}

@test "log_event writes a valid JSONL line to both files through sudo" {
    run log_event "test" "INFO" "hello"
    [ "$status" -eq 0 ]

    [ -f "${LOG_DIR}/grid-system.log" ]
    [ -f "${LOG_DIR}/grid-events.jsonl" ]

    # The append went through sudo, not a direct write.
    grep -q 'tee' "$_sudo_calls"

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

@test "log_event names the failure when sudo is unavailable" {
    # A LOG_DIR the caller cannot write plus a failing sudo: the write can
    # never succeed, so the failure must be reported by name.
    local readonly_dir="${BATS_TEST_TMPDIR}/readonly-log"
    mkdir -p "$readonly_dir"
    chmod 555 "$readonly_dir"
    export LOG_DIR="$readonly_dir"

    sudo() { echo "$*" >> "$_sudo_calls"; return 1; }
    export -f sudo

    run log_event "test" "ERROR" "boom"
    [ "$status" -ne 0 ]

    # Both the emitter and the cause appear on stderr.
    [[ "$output" == *"log_event"* ]]
    [[ "$output" == *"sudo"* ]]

    # Not discarded in silence: no event line reached the file.
    [ ! -s "${readonly_dir}/grid-events.jsonl" ]
}

@test "setup runs once per process while each write stays separate" {
    # Read-only LOG_DIR that exists but the current user cannot write, plus a
    # sudo stub that never succeeds: setup can never take effect, which is
    # exactly the path that used to re-run sudo on every call.
    local readonly_dir="${BATS_TEST_TMPDIR}/readonly-log"
    mkdir -p "$readonly_dir"
    chmod 555 "$readonly_dir"
    export LOG_DIR="$readonly_dir"

    sudo() { echo "$*" >> "$_sudo_calls"; "$@" 2>/dev/null || true; }
    export -f sudo

    log_event "test" "ERROR" "1" || true
    local setup_after_first
    setup_after_first="$(setup_calls_count)"

    local i
    for i in 2 3 4 5; do
        log_event "test" "ERROR" "$i" || true
    done
    local setup_after_all
    setup_after_all="$(setup_calls_count)"

    # Setup was attempted (>0) but never repeated across the five calls.
    [ "$setup_after_first" -gt 0 ]
    [ "$setup_after_first" -eq "$setup_after_all" ]
    [ "$setup_after_first" -le 3 ]

    # The writes are a separate path: one tee per call, not folded into setup.
    [ "$(grep -c 'tee' "$_sudo_calls")" -eq 5 ]
}

@test "rotate_logs rotates both grid-system.log and grid-events.jsonl" {
    # Tiny threshold so a couple of KB is "over the limit"; the test exercises
    # the real _lib.sh rotate_logs, not a reimplementation.
    export MAX_SIZE_KB=1

    local sys_log="${LOG_DIR}/grid-system.log"
    local evt_log="${LOG_DIR}/grid-events.jsonl"

    dd if=/dev/zero of="$sys_log" bs=1024 count=2 2>/dev/null
    dd if=/dev/zero of="$evt_log" bs=1024 count=2 2>/dev/null

    run rotate_logs
    [ "$status" -eq 0 ]

    [ -f "${sys_log}.old" ]
    [ -f "${evt_log}.old" ]

    # Fresh files are recreated (not just renamed away).
    [ -f "$sys_log" ]
    [ -f "$evt_log" ]
}

setup_calls_count() {
    grep -Ec 'mkdir|chown|chmod|touch' "$_sudo_calls" || true
}
