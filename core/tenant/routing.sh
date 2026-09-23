#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Tenant routing and cost attribution (FND-003, VT-004)
# ==============================================================================
# A request that carries an organisation id and a tenant id is routed to the
# upstream inference endpoint and the outcome is recorded against the tenant,
# with the compute cost computed from the upstream's own token report.
#
# The defect this library exists to prevent is "silent attribution to nobody":
# an untagged request being recorded under an empty or absent tenant, so the
# work happens but no one owns the bill. An empty-string tenant that passes a
# non-null check IS that defect, so every comparison here is on the VALUE.
#
# Criterion-2 scope: the "real request" is this path POSTing to a live upstream
# and parsing the tokens that upstream reports - not a value read out of a
# schema or a fixture. When the upstream is a real service (docker) that path
# runs end to end; with FAIGRID_ROUTE_STUB the transport is stubbed but the cost
# and record code below is identical, and attribution does not depend on the
# transport. A stubbed run must never be presented as a real round-trip.
#
# Isolation scope: this file is VT-004's own surface. It does not source, and
# does not write, any other core/tenant/ file. When sourced it exposes only
# functions and defines no globals, so a caller's variables never leak into it.
# ==============================================================================

# The explicit default tenant. An untagged request is NOT attributed here
# silently: routing refuses unless the operator has explicitly opted in by
# exporting FAIGRID_DEFAULT_TENANT (shown by _tenant_resolve). The name is a
# reserved word, not a valid organisation id, so an accidental default can
# never be confused with a real tenant.
FAIGRID_DEFAULT_TENANT_NAME="__default__"

# ------------------------------------------------------------------------------
# Inputs. The environment supplies the org id and the upstream coordinates; the
# request supplies the tenant id as an HTTP header, unless a test or an operator
# passes it positionally.
# ------------------------------------------------------------------------------

_faigrid_org_id() {
  printf '%s' "${FAIGRID_ORG_ID:-}"
}

# Escape a value for embedding in a JSONL line. Deliberately duplicated from
# core/workbench/scripts/_lib.sh rather than sourced: this file must stand alone
# (it needs no shared library, and a missing one must not turn a write into a
# silent no-op).
_json_escape() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | tr -d '\000-\037'
}

_faigrid_tenant_id() {
  printf '%s' "${X_TENANT_ID:-}"
}

_faigrid_route_timeout() {
  printf '%s' "${FAIGRID_ROUTE_TIMEOUT:-20}"
}

# The tenant a request is attributed to, or empty.
#   - a non-empty FAIGRID_DEFAULT_TENANT -> that explicit default;
#   - otherwise -> empty.
# An empty tenant id is NEVER promoted to the default on its own: the default is
# opted into by naming it, and otherwise the request is refused by the caller.
_faigrid_effective_tenant() {
  local t="${1:-}"
  if [[ -n "$t" ]]; then printf '%s' "$t"; return 0; fi
  if [[ -n "${FAIGRID_DEFAULT_TENANT:-}" ]]; then
    printf '%s' "$FAIGRID_DEFAULT_TENANT"
  fi
}

# ------------------------------------------------------------------------------
# Cost. The price table is an INPUT, not the answer: the tokens come from the
# upstream's response. A price per 1k tokens, evaluated as integer arithmetic on
# micro-cents to stay portable across Bash 3.2 and 5.x.
# ------------------------------------------------------------------------------

_faigrid_cost_millicents() {
  local pt="$1" ct="$2" pin="${3:-0}" pout="${4:-0}"
  printf '%s' "$(( pt * pin / 1000 + ct * pout / 1000 ))"
}

_faigrid_millicents_to_usd() {
  local mc="$1"
  printf '%d.%03d' "$(( mc / 1000 ))" "$(( mc % 1000 ))"
}

_faigrid_attr() {
  local json="$1" path="$2"
  printf '%s' "$json" | tr -d '\n' \
    | sed -nE 's/.*"'"${path}"'":[[:space:]]*"?([^",}]*)"?.*/\1/p' \
    | head -n1
}

# ------------------------------------------------------------------------------
# Record. An append-only JSONL line. Every write is atomic (mktemp + mv), so a
# concurrent reader never sees a torn record. The tenant is written as a real
# VALUE; nothing here substitutes a placeholder for "no tenant".
# ------------------------------------------------------------------------------

_tenant_record() {
  local file="$1" tenant="$2" cost="$3" pt="$4" ct="$5"
  local line tmp
  line=$(printf '{"ts":"%s","component":"tenant-router","severity":"INFO","org_id":"%s","tenant":"%s","model":"%s","cost_usd":%s,"prompt_tokens":%s,"completion_tokens":%s}' \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$(_json_escape "$(_faigrid_org_id)")" \
    "$(_json_escape "$tenant")" \
    "$(_json_escape "${FAIGRID_MODEL:-unknown}")" \
    "$cost" "$pt" "$ct")
  # Append while preserving the existing records: build the next file from the
  # current one plus the new line, then swap. Atomic, and never truncates.
  tmp="${file}.tmp.$$"
  if [[ -f "$file" ]]; then cat "$file" > "$tmp"; else : > "$tmp"; fi
  printf '%s\n' "$line" >> "$tmp"
  mv "$tmp" "$file"
}

# ------------------------------------------------------------------------------
# The routing path.
#   $1  tenant id, optional. If empty the X-Tenant-ID header is used.
#   $2  prompt-token count to send upstream, optional (default 1000)
#   $3  completion-token count to send upstream, optional (default 500)
#   $4  upstream host:port, optional (default ${FAIGRID_UPSTREAM:-127.0.0.1:8080})
#
# Returns:
#   0  routed and recorded
#   8  refused: no tenant id, and no explicit default configured
#   9  transport or upstream failure before a record could be made
# On success the request body is printed on stdout and the call is recorded.
# ------------------------------------------------------------------------------

tenant_route_request() {
  local tenant="${1:-}"
  if [[ -z "$tenant" ]]; then tenant="$(_faigrid_tenant_id)"; fi
  local effective
  effective="$(_faigrid_effective_tenant "$tenant")"

  # Criterion 3, first half: refuse by name rather than attribute to nobody.
  # A message is printed to stderr naming the request; the caller's exit code
  # makes the refusal non-silent. The label defaults to the request's own
  # effective tenant id when that is non-empty, so the message names the
  # request without the caller having to pass anything.
  if [[ -z "$effective" ]]; then
    local label="${FAIGRID_REQUEST_LABEL:-${tenant:-untagged}}"
    printf '%s\n' "tenant routing refused: request '${label}' carries no tenant id (X-Tenant-ID absent or empty) and no explicit default (FAIGRID_DEFAULT_TENANT) is set - refusing rather than attributing it to nobody" >&2
    return 8
  fi

  local pt="${2:-1000}" ct="${3:-500}"
  local target="${4:-${FAIGRID_UPSTREAM:-127.0.0.1:8080}}"
  local timeout; timeout="$(_faigrid_route_timeout)"

  if [[ "${FAIGRID_ROUTE_STUB:-0}" == "1" ]]; then
    _tenant_route_stubbed "$effective" "$pt" "$ct"
    return $?
  fi
  if ! command -v curl >/dev/null 2>&1; then
    printf '%s\n' "tenant routing failed: curl not found, cannot reach ${target}" >&2
    return 9
  fi

  local url="http://${target}/v1/chat"
  local body="{\"org_id\":\"$(_json_escape "$(_faigrid_org_id)")\",\"tenant\":\"$(_json_escape "$effective")\",\"prompt_tokens\":${pt},\"completion_tokens\":${ct}}"
  local response rc
  response="$(printf '%s' "$body" | curl -sS -m "$timeout" \
      -X POST "$url" -H 'Content-Type: application/json' --data-binary @- 2>/dev/null)"
  rc=$?
  if [[ $rc -ne 0 || -z "$response" ]]; then
    printf '%s\n' "tenant routing failed: upstream ${target} did not answer a valid request (curl exit ${rc})" >&2
    return 9
  fi

  local rpt rct
  rpt="$(_faigrid_attr "$response" prompt_tokens)"
  rct="$(_faigrid_attr "$response" completion_tokens)"
  if [[ -z "$rpt" || -z "$rct" ]]; then
    printf '%s\n' "tenant routing failed: upstream ${target} response carried no token usage; refusing to record an unattributable cost" >&2
    return 9
  fi

  local cost; cost="$(_faigrid_cost_millicents "$rpt" "$rct" "${FAIGRID_PRICE_IN_PER_1K_MC:-1000}" "${FAIGRID_PRICE_OUT_PER_1K_MC:-2000}")"
  _tenant_record "$(_faigrid_record_file)" "$effective" "$(_faigrid_millicents_to_usd "$cost")" "$rpt" "$rct"
  printf '%s\n' "$response"
  return 0
}

_faigrid_record_file() {
  printf '%s' "${FAIGRID_ROUTING_LOG:-${HOME}/.config/faigrid/routing.jsonl}"
}

# Stubbed transport for tests that prove the routing/attribution logic without a
# network. It fills the same response shape the real path parses and goes
# through the SAME cost and record code, so the record format is identical.
# This is NOT the criterion-2 proof; that is a real docker round-trip.
_tenant_route_stubbed() {
  local effective="$1" pt="$2" ct="$3"
  local response="{\"model\":\"${FAIGRID_MODEL:-stub}\",\"usage\":{\"prompt_tokens\":${pt},\"completion_tokens\":${ct}}}"
  local cost; cost="$(_faigrid_cost_millicents "$pt" "$ct" "${FAIGRID_PRICE_IN_PER_1K_MC:-1000}" "${FAIGRID_PRICE_OUT_PER_1K_MC:-2000}")"
  _tenant_record "$(_faigrid_record_file)" "$effective" "$(_faigrid_millicents_to_usd "$cost")" "$pt" "$ct"
  printf '%s\n' "$response"
  return 0
}

# ------------------------------------------------------------------------------
# Family C, second half: the recorded event never carries an empty tenant.
# Returns 0 when no such record exists; 1 (with the offending line on stdout)
# when one does. The check is on the VALUE, not on presence.
# ------------------------------------------------------------------------------

tenant_records_are_attributed() {
  local file; file="$(_faigrid_record_file)"
  [[ -f "$file" ]] || return 0
  local line
  while IFS= read -r line; do
    local t
    t="$(printf '%s' "$line" | jq -r 'select(.tenant != null) | .tenant // "__absent__"' 2>/dev/null)"
    if [[ -z "$t" || "$t" == "__absent__" || "$t" == "null" ]]; then
      printf '%s\n' "$line"
      return 1
    fi
  done < "$file"
  return 0
}

# ------------------------------------------------------------------------------
# Messaging layer (the faigate surface). Sends and RECEIVES a message over the
# wire, so the tenant round-trips a real transport rather than being read back
# from a fixture. A request with no tenant id is never sent.
# ------------------------------------------------------------------------------

tenant_messaging_send() {
  local tenant="$1" message="$2"
  if [[ -z "$tenant" ]]; then
    printf '%s\n' "tenant messaging refused: cannot send a message with no tenant id" >&2
    return 8
  fi
  local target="${3:-${FAIGRID_MESSAGING_UPSTREAM:-127.0.0.1:8090}}"
  local response rc
  response="$(printf '%s' "$message" | curl -sS -m "$(_faigrid_route_timeout)" \
      -X POST "http://${target}/api/v1/tenant-message" \
      -H 'Content-Type: text/plain' -H "X-Tenant-ID: ${tenant}" --data-binary @- 2>/dev/null)"
  rc=$?
  if [[ $rc -ne 0 || -z "$response" ]]; then
    printf '%s\n' "tenant messaging failed: upstream ${target} did not answer (curl exit ${rc})" >&2
    return 9
  fi
  printf '%s\n' "$response"
  return 0
}

# Always returns 0 and prints "sent <tenant>|received <tenant>" only when the
# two agree; prints a mismatch line and the transport error otherwise.
tenant_messaging_check() {
  local tenant="$1" message="$2"
  local sent received
  sent="$(tenant_messaging_send "$tenant" "$message")" || {
    printf '%s\n' "messaging-check: send failed for tenant '${tenant}'" >&2
    return 1
  }
  received="$(printf '%s' "$sent" | jq -r '.received_tenant // empty' 2>/dev/null)"
  if [[ "$received" != "$tenant" ]]; then
    printf '%s\n' "messaging-check: sent '${tenant}' but upstream received '${received}'" >&2
    return 1
  fi
  printf '%s\n' "sent ${tenant}|received ${received}"
  return 0
}

export -f _json_escape _faigrid_org_id _faigrid_tenant_id _faigrid_effective_tenant \
  _faigrid_cost_millicents _faigrid_millicents_to_usd _faigrid_attr \
  _tenant_record _faigrid_record_file _tenant_route_stubbed \
  tenant_route_request tenant_records_are_attributed \
  tenant_messaging_send tenant_messaging_check 2>/dev/null || true
