#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

# ==============================================================================
# Recovery journal (VT-006 / D3)
#
# The journal is the transport; the Z0 webhook push is a latency optimisation.
# These cases prove:
#   1. a worker restart writes a FaiGridRecoveryEvent that carries the ORIGINAL
#      correlation_id, compared literally;
#   2. the write position is readable and a deliberately skipped write is a gap
#      the consumer detects from its own cursor;
#   3. with the Z0 webhook refusing, the event is BOTH in the journal AND the job
#      continues - asserted together, never either half alone.
#
# The library is sourced inside each test, not in setup, so that a missing or
# broken core/tenant/recovery-journal.sh fails with the named assertion below
# instead of a bare source error. That is the red-proof entry point.
# ==============================================================================

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export RJ_LIB="${REPO_ROOT}/core/tenant/recovery-journal.sh"

    # Sandbox the journal so no test touches /var/lib.
    export RECOVERY_JOURNAL_DIR="${BATS_TEST_TMPDIR}/journal"
    mkdir -p "$RECOVERY_JOURNAL_DIR"

    # Z0 unreachable: a stubbed curl records the attempt, then refuses.
    export RECOVERY_JOURNAL_WEBHOOK_URL="http://127.0.0.1:1/z0/recovery"
    export RECOVERY_JOURNAL_WEBHOOK_TIMEOUT=1
    export _curl_calls="${BATS_TEST_TMPDIR}/curl_calls"
    : > "$_curl_calls"
    curl() { printf '%s\n' "$*" >> "$_curl_calls"; return 7; }
    export -f curl
}

@test "C1: a worker restart appends FaiGridRecoveryEvent with the SAME correlation_id" {
    source "$RJ_LIB"

    local worker="z1-worker-7"
    local corr="corr-veeona-abc"

    recovery_journal_record_job "$worker" "$corr"
    # A different worker's job must not be borrowed by the restart below.
    recovery_journal_record_job "z1-worker-9" "corr-other-xyz"

    recovery_journal_restart "$worker"

    local journal
    journal="$(rj_journal_file)"

    local original recovered
    original="$(jq -r --arg w "$worker" 'select(.worker == $w) | .correlation_id' "$journal" | head -n 1)"
    recovered="$(jq -r --arg w "$worker" 'select(.event_type == "FaiGridRecoveryEvent" and .worker == $w) | .correlation_id' "$journal" | tail -n 1)"

    # Literal string equality of the SAME id - not "an id is present".
    [ "$original" == "$corr" ]
    [ "$recovered" == "$original" ]
    [ "$recovered" == "$corr" ]

    # The appended record really is a FaiGridRecoveryEvent.
    run jq -e 'select(.event_type == "FaiGridRecoveryEvent")' "$journal"
    [ "$status" -eq 0 ]

    # The foreign worker's id never leaked into the recovery event.
    [ "$recovered" != "corr-other-xyz" ]
}

@test "C2: write position is readable and a skipped write is a gap from the cursor" {
    source "$RJ_LIB"

    local worker="z1-worker-1"
    local corr="corr-a"

    recovery_journal_record_job "$worker" "$corr"
    recovery_journal_append "$worker" "$corr" "restart" "1"

    run recovery_journal_position
    [ "$output" -eq 2 ]

    # A write is deliberately skipped: seq 3 never lands, the next write is 4.
    recovery_journal_append "$worker" "$corr" "restart" "2" "4"

    run recovery_journal_position
    [ "$output" -eq 4 ]

    # veeona's cursor is 2. Comparing it with the readable records and the
    # published position exposes the missing seq 3.
    run recovery_journal_gap_from_cursor 2
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing seq 3"* ]]

    # A cursor already at the write position is caught up: no gap.
    run recovery_journal_gap_from_cursor 4
    [ "$status" -eq 0 ]
}

@test "C3: with the Z0 webhook refusing the event is journaled AND the job continues" {
    local worker="z1-worker-1"
    local corr="corr-veeona-0001"

    # The child runs under `set -e`: the trailing marker only prints if the
    # restart call returns success, which is the "job continues" half. The
    # journal line is asserted separately below - both halves, not either.
    run bash -eo pipefail -c \
        'source "$1"; recovery_journal_record_job "$2" "$3" >/dev/null 2>&1 || true; recovery_journal_restart "$2"; printf "%s\n" JOB_CONTINUED' \
        _ "$RJ_LIB" "$worker" "$corr"

    local journal="${RECOVERY_JOURNAL_DIR}/recovery.jsonl"
    [ -s "$journal" ] || fail "missing journal line: expected FaiGridRecoveryEvent correlation_id=${corr} in ${journal}"

    [ "$status" -eq 0 ] || fail "job did not continue after an unreachable Z0 webhook (status=${status}): ${output}"
    [[ "$output" == *JOB_CONTINUED* ]] || fail "job did not continue after an unreachable Z0 webhook: ${output}"

    # Half one: the event is in the journal, with the preserved id.
    run jq -e --arg c "$corr" \
        'select(.event_type == "FaiGridRecoveryEvent" and .correlation_id == $c)' "$journal"
    [ "$status" -eq 0 ]

    # The push was actually attempted and refused (push is not the transport).
    [ -s "$_curl_calls" ]
}

@test "journal write profile stays separate from log_event" {
    source "$RJ_LIB"

    # A writable LOG_DIR sandbox: log_event() would materialise its files here.
    export LOG_DIR="${BATS_TEST_TMPDIR}/log"
    mkdir -p "$LOG_DIR"

    recovery_journal_record_job "z1-worker-1" "corr-a"
    recovery_journal_restart "z1-worker-1"

    [ ! -e "${LOG_DIR}/grid-events.jsonl" ]
    [ ! -e "${LOG_DIR}/grid-system.log" ]
}
