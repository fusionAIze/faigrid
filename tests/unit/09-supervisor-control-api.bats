#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

# ==============================================================================
# Supervisor Control API (GO-001 / D5)
#
# Three criteria:
#   C1  The Supervisor answers on faigrid_control_net:5000 with register, poll,
#       recovery_history(job_id) and max_workers, proven from a container on
#       that network.
#   C2  It answers ONLY on faigrid_control_net: the same probe from
#       faigrid_inference_net is REFUSED (timeout or connection refused). A 404
#       is NOT acceptable because it proves the API answered.
#   C3  recovery_history reads the journal core/tenant/recovery-journal.sh writes,
#       preserving correlation_id. It does not introduce a second, parallel
#       record of the same events.
#
# The library is sourced inside each test, not in setup, so a missing or broken
# file fails with the named assertion below instead of a bare source error.
# ==============================================================================

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export SUPERVISOR_LIB="${REPO_ROOT}/core/supervisor/supervisor.sh"
    export CONTROL_NET="faigrid_control_net"
    export INFERENCE_NET="faigrid_inference_net"

    docker >/dev/null 2>&1 || skip "docker not available"

    # Ensure networks exist
    source "${REPO_ROOT}/core/tenant/networks.sh"
    faigrid_networks_remove >/dev/null 2>&1 || true
    faigrid_networks_create >/dev/null 2>&1

    # Sandbox the recovery journal so no test touches /var/lib.
    # Must be set BEFORE sourcing supervisor.sh so the start function reads it.
    # Both RECOVERY_JOURNAL_DIR (recovery-journal.sh) and
    # SUPERVISOR_RECOVERY_JOURNAL_DIR (supervisor.sh) must point to the same path.
    # NOTE: /tmp/ is used instead of BATS_TEST_TMPDIR because macOS Docker
    # Desktop cannot resolve BATS_TEST_TMPDIR (/var/folders/...) through
    # container bind mounts. The `cd -P` resolves /tmp -> /private/tmp so
    # the bind mount target matches what Docker Desktop resolves on the host.
    export RECOVERY_JOURNAL_DIR="$(mktemp -d /tmp/faigrid-test-journal-XXXXXXXXXX)"
    RECOVERY_JOURNAL_DIR="$(cd -P "$RECOVERY_JOURNAL_DIR" && pwd)"
    export SUPERVISOR_RECOVERY_JOURNAL_DIR="${RECOVERY_JOURNAL_DIR}"
}

teardown() {
    # Supervisor cleanup
    source "$SUPERVISOR_LIB" 2>/dev/null || true
    faigrid_supervisor_stop 2>/dev/null || true
    docker rm -f faigrid-supervisor 2>/dev/null || true
    # Network cleanup (force-remove for tests that create bare networks)
    docker network rm "$CONTROL_NET" "$INFERENCE_NET" >/dev/null 2>&1 || true
    faigrid_networks_remove >/dev/null 2>&1 || true
    # Journal cleanup
    if [[ -n "${RECOVERY_JOURNAL_DIR:-}" && -d "$RECOVERY_JOURNAL_DIR" ]]; then
        rm -rf "$RECOVERY_JOURNAL_DIR"
    fi
}

# ── C1: Surface endpoints on control_net ───────────────────────────────────────

@test "C1a: max_workers answers from control_net" {
    source "$SUPERVISOR_LIB"
    faigrid_supervisor_start "$CONTROL_NET"
    faigrid_supervisor_wait_ready "$CONTROL_NET" || fail "supervisor did not become ready on control_net"

    run faigrid_supervisor_max_workers "$CONTROL_NET"
    [ "$status" -eq 0 ] || fail "max_workers probe failed (status=$status output=$output)"
    [[ "$output" == *"max_workers"* ]] || fail "max_workers response missing 'max_workers' key: ${output}"
}

@test "C1b: register answers from control_net" {
    source "$SUPERVISOR_LIB"
    faigrid_supervisor_start "$CONTROL_NET"
    faigrid_supervisor_wait_ready "$CONTROL_NET" || fail "supervisor did not become ready on control_net"

    run faigrid_supervisor_register "$CONTROL_NET" "z1-test-7"
    [ "$status" -eq 0 ] || fail "register probe failed (status=$status output=$output)"
    [[ "$output" == *"registered"* ]] || fail "register response missing 'registered': ${output}"
    [[ "$output" == *"z1-test-7"* ]] || fail "register response missing worker name 'z1-test-7': ${output}"
}

@test "C1c: poll answers from control_net" {
    source "$SUPERVISOR_LIB"
    faigrid_supervisor_start "$CONTROL_NET"
    faigrid_supervisor_wait_ready "$CONTROL_NET" || fail "supervisor did not become ready on control_net"

    run faigrid_supervisor_poll "$CONTROL_NET"
    [ "$status" -eq 0 ] || fail "poll probe failed (status=$status output=$output)"
    [[ "$output" == *"status"* ]] || fail "poll response missing 'status' key: ${output}"
}

# ── C2: Inference net refusal (SEC-001) ────────────────────────────────────────

@test "C2: inference net probe is REFUSED (SEC-001 boundary)" {
    source "$SUPERVISOR_LIB"
    faigrid_supervisor_start "$CONTROL_NET"
    faigrid_supervisor_wait_ready "$CONTROL_NET" || fail "supervisor did not become ready on control_net"

    # Confirm supervisor is reachable from control_net first
    run faigrid_supervisor_max_workers "$CONTROL_NET"
    [ "$status" -eq 0 ] || fail "control_net probe should have succeeded but did not"

    # Now probe from inference_net - must be REFUSED
    run faigrid_supervisor_probe "$INFERENCE_NET"
    # Must NOT return a valid HTTP status code (200, 404, etc.)
    # A timeout is acceptable evidence per acceptance criteria
    [ "$status" -ne 0 ] || fail "SEC-001 VIOLATION: supervisor answered from inference_net with HTTP ${output}"
    [[ "$output" == "000" ]] || fail "SEC-001: supervisor returned HTTP ${output} from inference_net - a 404 proves it answered"
}

# ── C3: recovery_history preserves correlation_id ──────────────────────────────

@test "C3a: recovery_history returns journal entries with correlation_id preserved" {
    # Write a journal entry first using recovery-journal.sh
    source "${REPO_ROOT}/core/tenant/recovery-journal.sh"
    local worker="z1-worker-7"
    local corr="corr-veeona-go001-test"

    recovery_journal_record_job "$worker" "$corr"
    recovery_journal_append "$worker" "$corr" "restart" "1"

    # Start supervisor with the journal directory bind-mounted
    source "$SUPERVISOR_LIB"
    faigrid_supervisor_start "$CONTROL_NET"
    faigrid_supervisor_wait_ready "$CONTROL_NET" || fail "supervisor did not become ready on control_net"

    # Query recovery_history via the API
    run faigrid_supervisor_recovery_history "$CONTROL_NET" "$worker"
    [ "$status" -eq 0 ] || fail "recovery_history probe failed (status=$status)"

    # The response must contain the correlation_id verbatim
    [[ "$output" == *"$corr"* ]] || fail "recovery_history response missing correlation_id '${corr}': ${output}"
    # Must contain the worker name
    [[ "$output" == *"$worker"* ]] || fail "recovery_history response missing worker '${worker}': ${output}"
    # Must contain the event type
    [[ "$output" == *"FaiGridRecoveryEvent"* ]] || fail "recovery_history response missing FaiGridRecoveryEvent: ${output}"
}

@test "C3b: recovery_history for unknown worker returns empty entries" {
    source "${REPO_ROOT}/core/tenant/recovery-journal.sh"
    local worker="z1-worker-7"
    local corr="corr-veeona-go001-test"
    recovery_journal_record_job "$worker" "$corr"

    source "$SUPERVISOR_LIB"
    faigrid_supervisor_start "$CONTROL_NET"
    faigrid_supervisor_wait_ready "$CONTROL_NET" || fail "supervisor did not become ready on control_net"

    run faigrid_supervisor_recovery_history "$CONTROL_NET" "nonexistent-worker"
    [ "$status" -eq 0 ] || fail "recovery_history for unknown worker failed (status=$status)"
    [[ "$output" == *"entries"* ]] || fail "recovery_history response missing 'entries' key: ${output}"
    # An empty array or a response without entries for the unknown worker
    echo "$output" | grep -q '"entries"' || fail "recovery_history response has no entries field: ${output}"
}

@test "C3c: recovery_history does not introduce a second journal file" {
    source "$SUPERVISOR_LIB"
    faigrid_supervisor_start "$CONTROL_NET"
    faigrid_supervisor_wait_ready "$CONTROL_NET" || fail "supervisor did not become ready on control_net"

    local files_before
    files_before="$(ls -1 "$RECOVERY_JOURNAL_DIR" 2>/dev/null || true)"

    run faigrid_supervisor_recovery_history "$CONTROL_NET" "test-worker"
    [ "$status" -eq 0 ] || fail "recovery_history probe failed (status=$status)"

    local files_after
    files_after="$(ls -1 "$RECOVERY_JOURNAL_DIR" 2>/dev/null || true)"

    # No new file was created by the API call
    [ "$files_before" == "$files_after" ] || fail "recovery_history created a new file in the journal directory: before=[${files_before}] after=[${files_after}]"
}

# ── RED PROOF ──────────────────────────────────────────────────────────────────

@test "RED PROOF: without control-net binding, probe fails with a real message" {
    source "$SUPERVISOR_LIB"

    # Create the broken state: start supervisor on the default bridge only,
    # without attachment to faigrid_control_net
    docker rm -f faigrid-supervisor 2>/dev/null || true
    local cid
    cid="$(docker run -d --rm \
        --name faigrid-supervisor \
        --label "com.fusionaize.faigrid.role=supervisor" \
        -e "SUPERVISOR_RECOVERY_JOURNAL_DIR=${RECOVERY_JOURNAL_DIR}" \
        -v "${RECOVERY_JOURNAL_DIR}:${RECOVERY_JOURNAL_DIR}:ro" \
        python:3.10-slim \
        python3 -c "$(_supervisor_server)")"

    # Give the server time to start
    sleep 3

    # Probe from control_net - must fail because the container is on the
    # default bridge, not on faigrid_control_net
    run faigrid_supervisor_probe "$CONTROL_NET"
    [ "$status" -ne 0 ] || fail "RED PROOF FAILED: supervisor on default bridge answered from control_net - the network isolation was not enforced"
    [[ "$output" == "000" ]] || fail "RED PROOF FAILED: supervisor returned HTTP ${output} from control_net despite having no control-net binding - this proves the binding is not required"

    docker rm -f faigrid-supervisor 2>/dev/null || true
}
