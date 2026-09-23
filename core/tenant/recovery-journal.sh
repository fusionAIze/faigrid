#!/usr/bin/env bash
# ==============================================================================
# Tenant recovery journal (VT-006 / operator decision D3)
#
# An append-only LOCAL JSONL journal that a tenant consumer (veeona) polls with
# its OWN cursor. The party that needs the guarantee holds the read pointer, so
# a lost write cannot pass unnoticed: the producer publishes a monotonically
# increasing write position and the consumer compares it with the records it can
# actually read from its cursor.
#
#   * The journal is a SEPARATE write profile from log_event() in
#     core/workbench/scripts/_lib.sh. The operator separated the two on
#     2026-09-23. The journal write goes straight to the journal file and NEVER
#     routes through log_event(); _lib.sh is sourced only for output helpers and
#     the shared JSON escaper.
#   * The Z0 webhook push is a latency optimisation, never the transport. A
#     failed or unreachable push never rolls back the local write and never
#     aborts the caller: the job continues.
#
# Source this file; do NOT execute it directly.
# ==============================================================================

_RJ_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=/dev/null
. "${_RJ_SCRIPT_DIR}/../workbench/scripts/_lib.sh"

# ── Configuration (all env-overridable) ───────────────────────────────────────
# Defaults target the installed layout; tests and non-root callers redirect the
# whole journal with RECOVERY_JOURNAL_DIR.
_RJ_DEFAULT_DIR="/var/lib/faigrid/recovery"
_RJ_DEFAULT_WEBHOOK_URL="http://127.0.0.1:9120/z0/recovery"
_RJ_DEFAULT_WEBHOOK_TIMEOUT="2"

rj_journal_dir() {
  printf '%s\n' "${RECOVERY_JOURNAL_DIR:-${_RJ_DEFAULT_DIR}}"
}

rj_journal_file() {
  if [[ -n "${RECOVERY_JOURNAL_FILE:-}" ]]; then
    printf '%s\n' "${RECOVERY_JOURNAL_FILE}"
  else
    printf '%s\n' "$(rj_journal_dir)/recovery.jsonl"
  fi
}

rj_position_file() {
  if [[ -n "${RECOVERY_JOURNAL_POSITION_FILE:-}" ]]; then
    printf '%s\n' "${RECOVERY_JOURNAL_POSITION_FILE}"
  else
    printf '%s\n' "$(rj_journal_dir)/recovery.position"
  fi
}

# ── Public read surface ───────────────────────────────────────────────────────

# The journal write position: the highest seq the producer has committed to.
# veeona holds its own cursor (the last seq it consumed) and compares the two.
recovery_journal_position() {
  local pf
  pf="$(rj_position_file)"
  if [[ -f "$pf" ]]; then
    cat "$pf"
  else
    printf '0\n'
  fi
}

# Print every record with seq strictly greater than CURSOR, one JSON object per
# line. This is the raw material veeona reads; it never rewrites the journal.
recovery_journal_read_from() {
  local cursor="${1:-0}"
  local file
  file="$(rj_journal_file)"
  [[ -f "$file" ]] || return 0
  jq -c --argjson c "$cursor" 'select(.seq > $c)' "$file" 2>/dev/null
}

# Gap detection from the consumer's cursor alone. Uses the published write
# position plus the records actually present: any seq in (cursor, position] that
# cannot be read back is a gap. Exits non-zero and NAMES the first missing seq.
recovery_journal_gap_from_cursor() {
  local cursor="${1:-0}"
  local pos
  pos="$(recovery_journal_position)"
  if [[ "$cursor" -ge "$pos" ]]; then
    return 0
  fi

  local seqs
  seqs="$(recovery_journal_read_from "$cursor" | jq -r '.seq' 2>/dev/null)"

  local missing=""
  local expected=$((cursor + 1))
  while [[ "$expected" -le "$pos" ]]; do
    if ! printf '%s\n' "$seqs" | grep -qx "$expected"; then
      if [[ -z "$missing" ]]; then
        missing="$expected"
      fi
    fi
    expected=$((expected + 1))
  done

  if [[ -n "$missing" ]]; then
    error "recovery journal: gap detected from cursor ${cursor}: missing seq ${missing} (write position ${pos})"
    return 1
  fi
  return 0
}

# ── Public write surface ──────────────────────────────────────────────────────

# Record the origin of a job: the correlation_id a later restart must preserve.
recovery_journal_record_job() {
  local worker="$1"
  local correlation_id="$2"
  local cause="${3:-job}"
  _rj_append_event "FaiGridJobEvent" "$worker" "$correlation_id" "$cause" "0" ""
}

# Append a FaiGridRecoveryEvent. The optional 5th argument forces the seq
# (replay / an explicitly skipped write); normally the next seq is used.
recovery_journal_append() {
  local worker="$1"
  local correlation_id="$2"
  local cause="${3:-restart}"
  local restarts="${4:-1}"
  local forced_seq="${5:-}"
  _rj_append_event "FaiGridRecoveryEvent" "$worker" "$correlation_id" "$cause" "$restarts" "$forced_seq"
}

# A worker restart. The recovery event carries the worker's ORIGINAL
# correlation_id - read back from the journal unless the caller passes it.
recovery_journal_restart() {
  local worker="$1"
  local correlation_id="${2:-}"

  if [[ -z "$correlation_id" ]]; then
    correlation_id="$(recovery_journal_original_correlation_id "$worker")"
  fi
  if [[ -z "$correlation_id" ]]; then
    error "recovery journal: no original correlation_id recorded for worker '${worker}'"
    return 1
  fi

  local restarts
  restarts="$(recovery_journal_restart_count "$worker")"
  restarts=$((restarts + 1))

  recovery_journal_append "$worker" "$correlation_id" "restart" "$restarts"
}

# The most recent correlation_id recorded for WORKER - the value a restart must
# preserve. Stable across repeated restarts because recovery events carry it too.
recovery_journal_original_correlation_id() {
  local worker="$1"
  local file
  file="$(rj_journal_file)"
  [[ -f "$file" ]] || return 0
  jq -r --arg w "$worker" 'select(.worker == $w) | .correlation_id' "$file" 2>/dev/null | tail -n 1
}

recovery_journal_restart_count() {
  local worker="$1"
  local file
  file="$(rj_journal_file)"
  [[ -f "$file" ]] || { printf '0\n'; return 0; }
  jq -s --arg w "$worker" \
    '[.[] | select(.worker == $w and .event_type == "FaiGridRecoveryEvent")] | length' \
    "$file" 2>/dev/null || printf '0\n'
}

# ── Internals ─────────────────────────────────────────────────────────────────

_rj_append_event() {
  local event_type="$1"
  local worker="$2"
  local correlation_id="$3"
  local cause="$4"
  local restarts="$5"
  local forced_seq="$6"

  local dir file
  dir="$(rj_journal_dir)"
  file="$(rj_journal_file)"
  mkdir -p "$dir"

  local pos seq ts json max
  pos="$(recovery_journal_position)"
  if [[ -n "$forced_seq" ]]; then
    seq="$forced_seq"
  else
    seq=$((pos + 1))
  fi

  if [[ "$seq" -gt "$pos" ]]; then max="$seq"; else max="$pos"; fi

  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  json="$(printf '{"event_type":"%s","seq":%s,"ts":"%s","worker":"%s","correlation_id":"%s","cause":"%s","restart_count":%s}' \
    "$(_json_escape "$event_type")" \
    "$seq" \
    "$(_json_escape "$ts")" \
    "$(_json_escape "$worker")" \
    "$(_json_escape "$correlation_id")" \
    "$(_json_escape "$cause")" \
    "$restarts")"

  # Local append is the transport: it lands first and is never conditional on
  # the push. Position advances only after the record is durably in the file.
  printf '%s\n' "$json" >> "$file"

  local pf
  pf="$(rj_position_file)"
  printf '%s\n' "$max" > "${pf}.tmp.$$"
  mv "${pf}.tmp.$$" "$pf"

  _rj_push "$json" "$seq"
  return 0
}

# Best-effort push to Z0. ALWAYS returns 0: the local journal is the transport,
# the push is a latency optimisation, and the job must continue regardless.
_rj_push() {
  local json="$1"
  local seq="$2"
  local url="${RECOVERY_JOURNAL_WEBHOOK_URL:-${_RJ_DEFAULT_WEBHOOK_URL}}"
  local timeout="${RECOVERY_JOURNAL_WEBHOOK_TIMEOUT:-${_RJ_DEFAULT_WEBHOOK_TIMEOUT}}"

  if ! command -v curl >/dev/null 2>&1; then
    warn "recovery journal: curl unavailable; Z0 webhook push skipped (seq=${seq} retained locally, job continues)"
    return 0
  fi

  if curl -fsS --max-time "$timeout" -X POST \
      -H 'Content-Type: application/json' --data "$json" "$url" >/dev/null 2>&1; then
    return 0
  fi

  warn "recovery journal: Z0 webhook unreachable at ${url}; seq=${seq} retained locally, job continues"
  return 0
}
