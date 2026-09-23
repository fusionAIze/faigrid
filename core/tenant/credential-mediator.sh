#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Tenant credential mediator (VT-005 / operator decision D2)
# ==============================================================================
# SEC-001 and the CredentialBroker clause contradict each other: a z1 worker can
# be told "the broker (Z0, control plane) is unreachable" and "authenticate at the
# broker" at the same time only if some component resolves the contradiction.
# That component is a single, dual-homed, application-layer mediator.
#
#   control_net      trusted: the broker and the mediator's control interface
#   inference_net    untrusted: z1 workers and the mediator's inference interface
#
# The mediator is the ONLY container attached to both networks. It holds no
# long-lived secret: it relays a worker's request to the broker and returns a
# SCOPED token, bounded to the tenant and the scope the mediator grants it. The
# broker's own long-lived secret never crosses into the inference plane, and no
# worker's environment ever carries it.
#
# Criterion 1 is a proof by REFUSAL, not a config reading. net.ipv4.ip_forward
# reads 0 and 1 identically whether or not a forward actually succeeds, so this
# file attempts a forward THROUGH the mediator (a probe on the inference side
# routes to the broker's control-net address via the mediator as next hop) and
# captures whether the broker is reached. With forwarding off the attempt is
# refused; with forwarding forced on it reaches the broker. The test asserts on
# that reachability, never on the sysctl value.
#
# Sourced from tests and the install path. It only performs work when a function
# is invoked. Bash 3.2 compatible (macOS + Linux).
# ==============================================================================

set -euo pipefail

_CM_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=networks.sh
. "${_CM_SCRIPT_DIR}/networks.sh"

# ── Mediator contract ──────────────────────────────────────────────────────────
# These names are the input to every function; they follow HTTP, not the events
# schema. The broker is veeona's CredentialBroker (Z0); the mediator is faigrid's
# client against veeona's HTTP spec.
FAIGRID_MEDIATOR_CTRL_PORT="8443"      # mediator listens here on the control net
FAIGRID_MEDIATOR_INF_PORT="8443"       # ... and the same port on the inference net
FAIGRID_BROKER_PORT="9000"             # the broker's listener (control net only)
FAIGRID_MEDIATOR_IMAGE="${FAIGRID_MEDIATOR_IMAGE:-python:3.10-slim}"
FAIGRID_BROKER_IMAGE="${FAIGRID_BROKER_IMAGE:-python:3.10-slim}"
FAIGRID_PROBE_IMAGE="${FAIGRID_PROBE_IMAGE:-busybox:latest}"

# The broker's long-lived secret. It lives ONLY in the broker's environment. The
# name is deliberate: a test that searches a worker's environment must search for
# this value, so the name is part of the contract even though the value is not.
FAIGRID_BROKER_SECRET_ENV="FAIGRID_BROKER_SECRET"

# Default long-lived secret for the broker in a test/topology run. Real operators
# override it. Tests may inject their own so the "secret searched for" is known.
_DEFAULT_BROKER_SECRET="veeona_broker_longlived_secret_7f2d"

# Default scoped token the mediator hands out. This is a SHORT-LIVED, tenant- and
# scope-bounded token, deliberately distinct in name from the broker secret: a
# dump of a worker's environment must never find either.
_DEFAULT_SCOPED_TOKEN="veeona_scoped_z1_token_9c1e"

# ── Logging (degrades to printf if _lib.sh is absent) ───────────────────────────
_cm_log() {
    if declare -f info >/dev/null 2>&1; then
        info "$*"
    else
        printf '%s\n' "$*"
    fi
}

# ── The two HTTP servers (broker and mediator) as inline python ────────────────
# Inline `python3 -c` so the test never depends on a bind-mount (Docker Desktop
# only shares whitelisted paths, and a stale mountpoint turns /srv.py into a
# directory). Both servers are stdlib-only: no image beyond a python base.

# The broker: exposes the long-lived secret to the control plane. It is the Z0
# surface a worker must NEVER reach directly.
_cm_broker_server() {
    printf '%s' 'import http.server,socketserver,json,os
SECRET=os.environ.get("FAIGRID_BROKER_SECRET","veeona_broker_longlived_secret_7f2d")
class H(http.server.BaseHTTPRequestHandler):
 def do_GET(self):
  if self.path=="/v1/broker/token":
   b=json.dumps({"token":SECRET,"scope":"z1","kind":"long_lived"}).encode()
   self.send_response(200);self.send_header("Content-Type","application/json");self.send_header("Content-Length",str(len(b)));self.end_headers();self.wfile.write(b)
  else:
   self.send_response(404);self.end_headers()
 def log_message(self,*a):pass
socketserver.ThreadingTCPServer(("0.0.0.0",9000),H).serve_forever()'
}

# The mediator: listens on BOTH networks, but only ever hands out a SCOPED token.
# It does not return the broker secret and does not proxy arbitrary traffic; its
# job is exactly the credential that the isolation model still lets a worker hold.
_cm_mediator_server() {
    printf '%s' 'import http.server,socketserver,json,os
SCOPED=os.environ.get("FAIGRID_SCOPED_TOKEN","veeona_scoped_z1_token_9c1e")
class H(http.server.BaseHTTPRequestHandler):
 def do_POST(self):
  if self.path=="/v1/mediator/token":
   n=int(self.headers.get("Content-Length",0));self.rfile.read(n)
   b=json.dumps({"scoped_token":SCOPED,"tenant":"veeona-hq","scope":"z1-inference","kind":"scoped"}).encode()
   self.send_response(200);self.send_header("Content-Type","application/json");self.send_header("Content-Length",str(len(b)));self.end_headers();self.wfile.write(b)
  else:
   self.send_response(404);self.end_headers()
 def log_message(self,*a):pass
socketserver.ThreadingTCPServer(("0.0.0.0",8443),H).serve_forever()'
}

# ── Docker helpers (input: network names from networks.sh) ─────────────────────

# True if docker is usable. The mediator proof is a real container topology, so a
# missing docker means the criterion is INCONCLUSIVE, never silently passed.
_cm_docker_available() {
    command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

# The IP a container holds on a given network, or empty.
_cm_container_ip() {
    local cid="$1" net="$2"
    docker inspect -f "{{(index .NetworkSettings.Networks \"${net}\").IPAddress}}" "$cid" 2>/dev/null || true
}

# Start the broker on the control net. Echoes its container id. The caller is
# responsible for teardown.
faigrid_mediator_broker_start() {
    local secret="${1:-$_DEFAULT_BROKER_SECRET}"
    docker run -d --rm --network "$FAIGRID_CONTROL_NET" \
        --label "com.fusionaize.faigrid.role=broker" \
        -e "${FAIGRID_BROKER_SECRET_ENV}=${secret}" \
        "$FAIGRID_BROKER_IMAGE" python3 -c "$(_cm_broker_server)"
}

# Start the mediator: the single dual-homed container. net.ipv4.ip_forward starts
# OFF. When FORCE_FORWARD is 1 the container is created with forwarding enabled -
# the red-proof state the criterion's broken world is built from. Echoes the
# container id.
faigrid_mediator_start() {
    local force_forward="${1:-0}"
    local scoped="${2:-$_DEFAULT_SCOPED_TOKEN}"
    local sysctl_flag=0
    if [[ "$force_forward" == "1" ]]; then
        sysctl_flag=1
    fi

    if [[ "$sysctl_flag" == "1" ]]; then
        docker run -d --rm \
            --cap-add NET_ADMIN \
            --sysctl net.ipv4.ip_forward=1 \
            --network "$FAIGRID_CONTROL_NET" \
            --network "$FAIGRID_INFERENCE_NET" \
            --label "com.fusionaize.faigrid.role=mediator" \
            -e "FAIGRID_SCOPED_TOKEN=${scoped}" \
            "$FAIGRID_MEDIATOR_IMAGE" python3 -c "$(_cm_mediator_server)"
    else
        docker run -d --rm \
            --cap-add NET_ADMIN \
            --sysctl net.ipv4.ip_forward=0 \
            --network "$FAIGRID_CONTROL_NET" \
            --network "$FAIGRID_INFERENCE_NET" \
            --label "com.fusionaize.faigrid.role=mediator" \
            -e "FAIGRID_SCOPED_TOKEN=${scoped}" \
            "$FAIGRID_MEDIATOR_IMAGE" python3 -c "$(_cm_mediator_server)"
    fi
}

# Remove a container by name (never errors if it is already gone).
faigrid_mediator_remove() {
    docker rm -f "$1" >/dev/null 2>&1 || true
}

# Wait until a host:port answers. The ready signal is a real HTTP round-trip from
# INSIDE the topology (busybox wget), never an exit-code-only sleep. Returns 0
# once ready, 1 after MAX_TRIES.
_cm_wait_http_ready() {
    local net="$1" url="$2" post_data="${3:-}"
    local tries="${4:-20}"
    local i
    for i in $(seq 1 "$tries"); do
        if [[ -n "$post_data" ]]; then
            if docker run --rm --network "$net" "$FAIGRID_PROBE_IMAGE" \
                wget -q -T 2 -O /dev/null --header 'Content-Type: application/json' \
                --post-data "$post_data" "$url" >/dev/null 2>&1; then
                return 0
            fi
        else
            if docker run --rm --network "$net" "$FAIGRID_PROBE_IMAGE" \
                wget -q -T 2 -O /dev/null "$url" >/dev/null 2>&1; then
                return 0
            fi
        fi
        sleep 1
    done
    return 1
}

# ── The client surface (runs on a worker, not inside the mediator) ─────────────
#
# A z1 worker asks the mediator for a scoped token. Returns the raw JSON body and
# exit 0 on success; exit 1 with a message on stdout/stderr otherwise. This is the
# ONLY path a worker owns: it has no code here that talks to the broker directly.
faigrid_mediator_obtain_token() {
    local mediator_ip="$1"
    local worker="${2:-z1}"
    local url="http://${mediator_ip}:${FAIGRID_MEDIATOR_INF_PORT}/v1/mediator/token"
    curl -sS -m 10 \
        -X POST "$url" \
        -H 'Content-Type: application/json' \
        --data "{\"worker\":\"${worker}\"}"
}

# A worker attempting the broker DIRECTLY. Returns exit 0 iff the broker answers
# (which is exactly the failure the isolation model forbids); exit 1 on a refused
# or timed-out connection. The caller compares the outcome, never the sysctl.
faigrid_mediator_direct_broker() {
    local broker_ip="$1"
    local url="http://${broker_ip}:${FAIGRID_BROKER_PORT}/v1/broker/token"
    curl -sS -m 10 "$url"
}

# ── Forward-probe surface (criterion 1) ────────────────────────────────────────
#
# Attempt a forward THROUGH the mediator: add a route on a throwaway inference
# probe container so the broker's control-net address is reached via the
# mediator's inference interface as next hop, then try to fetch the broker's
# token page. Returns:
#   0  the broker WAS reached (forward succeeded) - the broken state
#   1  the broker was NOT reached (forward refused) - the asserted state
# Echoes the probe's wget output on stdout, so the caller can name the reached
# host and tell "refused" from "timed out" apart in CONTENT, not only exit code.
faigrid_mediator_probe_forward() {
    local broker_ip="$1"
    local mediator_inf_ip="$2"
    local broker_cid="${3:-}"
    if [[ -z "$broker_cid" ]]; then broker_cid="$(faigrid_mediator_broker_start "$_DEFAULT_BROKER_SECRET")"; fi

    local probe_name="faigrid-forward-probe-$$"
    docker rm -f "$probe_name" >/dev/null 2>&1 || true
    local probe_cid
    probe_cid="$(docker run -d --rm --cap-add NET_ADMIN \
        --network "$FAIGRID_INFERENCE_NET" \
        --name "$probe_name" \
        "$FAIGRID_PROBE_IMAGE" sleep 300)"
    local probe_ip
    probe_ip="$(_cm_container_ip "$probe_cid" "$FAIGRID_INFERENCE_NET")"

    # Route the broker's address through the mediator. This is the "through the
    # mediator" part: without it the probe only ever tests docker's own bridge
    # isolation, not the mediator's forwarding decision.
    docker exec "$probe_cid" sh -c "ip route del ${broker_ip}/32 2>/dev/null; ip route add ${broker_ip}/32 via ${mediator_inf_ip}" >/dev/null 2>&1

    local out rc
    out="$(docker exec "$probe_cid" wget -T 4 -O - "http://${broker_ip}:${FAIGRID_BROKER_PORT}/v1/broker/token" 2>&1)"
    rc=$?

    docker rm -f "$probe_name" >/dev/null 2>&1 || true
    printf '%s\n' "$out"
    return "$rc"
}
