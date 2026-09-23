#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

# ==============================================================================
# core/tenant/routing.sh — tenant routing and cost attribution (FND-003, VT-004)
#
# The defect under test is SILENT ATTRIBUTION TO NOBODY. An empty-string tenant
# that passes a non-null check is exactly that defect, so every assertion here
# is on the VALUE of the tenant, never on its presence.
#
# C1  a request carrying FAIGRID_ORG_ID and X-Tenant-ID is routed and the tenant
#     is recorded.
# C2  cost is attributable to veeona-hq from a REAL request round-trip — two
#     docker containers on one bridge. A stub must never pass for this, so if
#     docker is unavailable the C2 test is skipped and the lane report marks
#     criterion 2 INCONCLUSIVE.
# C3  a request with no tenant id is refused by name, and NO record with an
#     empty tenant is ever written; an operator may instead name an explicit
#     default, which is then recorded literally as that default.
#
# Routing runs inside a container because this host's loopback/DNS cannot
# resolve a sibling container on the same bridge — the same topology a real
# faigrid node would use. The test therefore asserts on the routing library's
# behaviour through a container, not on a local curl.
# ==============================================================================

ROUTING="${REPO_ROOT:-${BATS_TEST_DIRNAME}/../..}/core/tenant/routing.sh"
UPSTREAM_IMAGE="${VT004_UPSTREAM_IMAGE:-python:3.12-alpine}"
CLIENT_IMAGE="${VT004_CLIENT_IMAGE:-debian:bookworm-slim}"

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export FAIGRID_ROUTING_LOG="${BATS_TEST_TMPDIR}/routing.jsonl"
    export FAIGRID_ORG_ID="veeona-hq"
    export FAIGRID_ROUTE_TIMEOUT=10

    # C1/C3 exercise the routing and attribution LOGIC. The transport is stubbed
    # here because a unit test owns no upstream; C2 runs the same code inside a
    # container against a REAL upstream and is the only test that may claim a
    # real round-trip.
    export FAIGRID_ROUTE_STUB=1

    source "$ROUTING"
}

# The tenant recorded on the last line of the routing log, literally.
last_recorded_tenant() {
    jq -r '.tenant' "$FAIGRID_ROUTING_LOG" 2>/dev/null | tail -n1
}

# ── C1 — a tagged request is routed and the tenant is recorded ────────────────

@test "C1: a request carrying org id and tenant id is routed and the tenant is recorded" {
    run tenant_route_request "veeona-hq"
    [ "$status" -eq 0 ]
    [ -s "$FAIGRID_ROUTING_LOG" ]

    # The recorded tenant is the literal value, not merely non-null.
    [ "$(last_recorded_tenant)" = "veeona-hq" ]
    [ "$(jq -r '.org_id' "$FAIGRID_ROUTING_LOG" | tail -n1)" = "veeona-hq" ]

    # The upstream response is passed through, so the request really completed.
    [[ "$output" == *'"usage"'* ]]
}

@test "C1: X-Tenant-ID is accepted as the request-level carrier" {
    export X_TENANT_ID="veeona-hq"
    unset FAIGRID_ORG_ID
    run tenant_route_request
    [ "$status" -eq 0 ]
    [ "$(last_recorded_tenant)" = "veeona-hq" ]
}

@test "C1: two different tenants are recorded under their own values" {
    tenant_route_request "veeona-hq" >/dev/null
    tenant_route_request "other-tenant" >/dev/null
    [ "$(jq -r '.tenant' "$FAIGRID_ROUTING_LOG" | sed -n '1p')" = "veeona-hq" ]
    [ "$(jq -r '.tenant' "$FAIGRID_ROUTING_LOG" | sed -n '2p')" = "other-tenant" ]
}

# ── C3 — no tenant id: refused, never silently attributed ─────────────────────

@test "C3: a request with no tenant id is refused by name and records nothing" {
    run tenant_route_request ""
    # Name the offending record if one was written, so the failure says WHY.
    if [ -s "$FAIGRID_ROUTING_LOG" ]; then
        printf 'FAIL: untagged request was recorded rather than refused: %s\n' \
            "$(cat "$FAIGRID_ROUTING_LOG")" >&2
    fi
    [ "$status" -eq 8 ]
    # The refusal names the missing tenant rather than failing silently.
    [[ "$output" == *"refused"* ]]
    [[ "$output" == *"no tenant id"* ]]
    # Nothing was recorded: no record with an empty tenant exists.
    [ ! -s "$FAIGRID_ROUTING_LOG" ]
}

@test "C3: an empty-string tenant is refused, not treated as a valid tenant" {
    # The empty string is the exact defect: a NON-NULL value that names nobody.
    run tenant_route_request ""
    if [ -s "$FAIGRID_ROUTING_LOG" ]; then
        printf 'FAIL: empty-string tenant was silently recorded as: %s\n' \
            "$(cat "$FAIGRID_ROUTING_LOG")" >&2
    fi
    [ "$status" -eq 8 ]
    [ ! -s "$FAIGRID_ROUTING_LOG" ]
}

@test "C3: an untagged request is not silently recorded after a tagged one" {
    # Guards the realistic regression: the first (tagged) request must not leave
    # the log in a state where the second (untagged) one is attributed to it.
    tenant_route_request "veeona-hq" >/dev/null
    run tenant_route_request ""
    [ "$status" -eq 8 ]
    # Exactly one record exists, and it belongs to the tagged request only.
    [ "$(wc -l < "$FAIGRID_ROUTING_LOG" | tr -d ' ')" -eq 1 ]
    [ "$(last_recorded_tenant)" = "veeona-hq" ]
}

@test "C3: tenant_records_are_attributed rejects a record with an empty tenant" {
    _tenant_record "$FAIGRID_ROUTING_LOG" "" "0.000" "0" "0"
    run tenant_records_are_attributed
    [ "$status" -eq 1 ]
    [[ "$output" == *'"tenant":""'* ]]
}

@test "C3: tenant_records_are_attributed accepts records that name a tenant" {
    tenant_route_request "veeona-hq" >/dev/null
    run tenant_records_are_attributed
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "C3: an explicit default is recorded literally when the operator names it" {
    export FAIGRID_DEFAULT_TENANT="__default__"
    run tenant_route_request ""
    [ "$status" -eq 0 ]
    # The recorded value is the default's literal name, not the empty string.
    [ "$(last_recorded_tenant)" = "__default__" ]
    # And the default is not a value a real tenant could collide with.
    [ "$(last_recorded_tenant)" != "" ]
}

# ── C2 — cost attributable to veeona-hq from a real request round-trip ────────

vt004_docker_available() {
    command -v docker >/dev/null 2>&1 \
        && docker info >/dev/null 2>&1
}

# Start a token-counting upstream and a client that can run bash+jq+curl on the
# same bridge. Echoes "upip cli" on success. Caller must teardown.
vt004_start_roundtrip() {
    local up="vt004bats-upstream" cli="vt004bats-client"

    docker run -d --name "$up" --network bridge "$UPSTREAM_IMAGE" sh -c '
cat > /srv.py <<PY
import http.server, json, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0)); body = self.rfile.read(n)
        try: data = json.loads(body or b"{}")
        except Exception: data = {}
        out = {"model": "deepseek-v4-flash",
               "usage": {"prompt_tokens": int(data.get("prompt_tokens", 0)),
                         "completion_tokens": int(data.get("completion_tokens", 0))}}
        b = json.dumps(out).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
class S(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
S(("0.0.0.0", 8080), H).serve_forever()
PY
python3 /srv.py' >/dev/null

    # Wait until the upstream answers a POST from inside its own container.
    local i
    for i in $(seq 1 30); do
        docker exec "$up" python3 -c \
            'import urllib.request,json;urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8080/v1/chat",data=b"{}"))' >/dev/null 2>&1 && break
        sleep 1
    done

    docker run -d --name "$cli" --network bridge -v "${REPO_ROOT}/core:/core:ro" \
        --entrypoint sleep "$CLIENT_IMAGE" 600 >/dev/null
    for i in $(seq 1 30); do
        docker exec "$cli" sh -c 'command -v bash >/dev/null && command -v jq >/dev/null && command -v curl >/dev/null' && break
        # minimal bootstrap if the image lacks the tools
        docker exec "$cli" sh -c 'apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq bash jq curl >/dev/null 2>&1' >/dev/null 2>&1 || true
        sleep 1
    done

    echo "$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$up") $cli"
}

vt004_teardown_roundtrip() {
    docker rm -f vt004bats-upstream vt004bats-client >/dev/null 2>&1 || true
}

@test "C2: cost is attributable to veeona-hq from a real request round-trip" {
    if ! vt004_docker_available; then
        skip "docker unavailable: criterion 2 is INCONCLUSIVE, not passed"
    fi

    local info upip cli record
    info="$(vt004_start_roundtrip)"
    upip="${info%% *}"; cli="${info##* }"

    # Run the REAL routing path inside the client container, against the live
    # upstream. This is the round-trip: tokens come back from the upstream.
    run docker exec -e FAIGRID_ORG_ID="veeona-hq" -e FAIGRID_ROUTING_LOG=/tmp/routing.jsonl \
        "$cli" bash -c "
            set -e
            source /core/tenant/routing.sh
            tenant_route_request 'veeona-hq' 1000 500 '${upip}:8080' >/dev/null
            cat /tmp/routing.jsonl"

    vt004_teardown_roundtrip

    [ "$status" -eq 0 ]
    record="$output"

    # The cost and the tenant are both present, and the tenant is literal.
    echo "$record" | jq -e '.tenant == "veeona-hq"' >/dev/null
    echo "$record" | jq -e '.org_id == "veeona-hq"' >/dev/null
    # The token counts are the upstream's own report, and the cost follows from
    # them: 1000 in + 500 out at 1.000/2.000 USD per 1k = 2.000.
    echo "$record" | jq -e '.prompt_tokens == 1000' >/dev/null
    echo "$record" | jq -e '.completion_tokens == 500' >/dev/null
    echo "$record" | jq -e '.cost_usd == "2.000" or .cost_usd == 2.0' >/dev/null
}

@test "C2: teardown leaves no vt004bats container behind" {
    vt004_docker_available || skip "docker unavailable"
    run docker ps -a --format '{{.Names}}'
    [[ "$output" != *"vt004bats-upstream"* ]]
    [[ "$output" != *"vt004bats-client"* ]]
}
