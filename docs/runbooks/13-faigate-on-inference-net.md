# Step 13 — faigate on the inference net (GO-002)

Scope: make the gate reachable to the tenant inference plane as
`http://faigate:8090/v1`, so that veeona's z1 and z2 zones — which address
exactly that URL — find it. This is a **deployment**, not a verification: before
this lane, `faigrid_inference_net` held zero containers and no faigate ran on
`nexus-core`. This is lane **GO-002** of sequence `veeona-golive`, phase 0,
serialized against GO-001 because both create containers on the same daemon.

Host: `nexus-core` (192.168.178.20, user `nexus`, key `~/.ssh/id_ed25519`).

## 1. Why a container, not a host process

`faigate:8090` must resolve from inside the tenant's z1/z2 containers. A name on
a Docker network resolves through Docker's embedded DNS only for containers
attached to that network, so the gate has to be a container joined to
`faigrid_inference_net`. A faigate process on the host would need a published
port and would be reachable from every plane at once — the opposite of the
SEC-001 separation. The deployed service publishes **no host port** and joins
**exactly one** network.

## 2. The deployment file

Two copies, byte-identical:

1. **Repo copy (committed, secret-free):**
   `external/compose/faigate-inference.yml`.
2. **Node copy (the durable operand, written by this lane, NOT committed):**
   `/home/nexus/faigate-inference/faigate-inference.yml` — owner `nexus:nexus`,
   mode 644.

The node copy is what `docker compose` on the node points at; the running
container's `com.docker.compose.project.config_files` label reads that path.

Project and container: project `faigate-inference`, container `faigate`.

## 3. Why the inline config is required

faigate's shipped default binds `server.host: 127.0.0.1`. Inside a container that
is the container's own loopback and would be unreachable from the inference
plane, so the compose file carries one `configs` block overriding `server.host`
to `0.0.0.0` on port `8090`. Nothing else is overridden: faigate's model catalog
is compiled into the image, so `/v1/models` answers with a catalog model list
**without any provider credential** (measured: 91 entries). No secret is
required for this deployment and none is written into either copy.

```
configs:
  faigate_server_config:
    content: |
      server:
        host: 0.0.0.0
        port: 8090
        log_level: info
```

## 4. Image provenance

faigate is not published as an anonymously pullable image (`ghcr.io` answers 401
unauthenticated, indistinguishable from private or absent), so the image is
built from faigate's canonical source. The release tag `v2.9.3` is not
immutable, so the build context is pinned to the commit the tag points at:

```
context: https://github.com/fusionAIze/faigate.git#c8404484a3d1697fa821cf45349d570d859b25f8
```

Build (once, on the node; ~1.5 min):

```bash
cd /home/nexus/faigate-inference
docker compose -f faigate-inference.yml build      # -> faigate:2.9.3
docker compose -f faigate-inference.yml up -d
```

## 5. Criterion 1 — reachable on the inference net

Probe, run on `nexus-core`:

```bash
docker run --rm --net faigrid_inference_net curlimages/curl \
  -s -o /dev/null -w '%{http_code}' http://faigate:8090/v1/models
# 200
```

The body is an OpenAI-compatible list object carrying a model catalog:

```json
{"object":"list","data":[{"object":"model","owned_by":"faigate",
 "description":"Catalog model anthropic/claude-opus-4-7", ... }]}
```

Measured: **91** `"object":"model"` entries. No provider key is involved.

## 6. Criterion 2 — refused from the control net

The same target is unreachable from `faigrid_control_net`, proven by two
connection attempts and not by reading the compose. Both kinds of refusal are
captured; neither is an HTTP status (a 404 would prove the gate answered):

| Probe from `faigrid_control_net` | Result |
| --- | --- |
| by DNS name `http://faigate:8090/v1/models` | `curl: (6) Could not resolve host: faigate` — the name is not on the control network's DNS |
| by the gate's inference-network IP `172.20.0.2:8090` | `curl: (28) Connection timed out after 8001 milliseconds` — the address does not answer across networks |

The test carries an in-file positive control (the same URL answered `200` on
`faigrid_inference_net` in the same run), so a dead gate can never read as a
successful refusal.

## 7. Criterion 3 — the five incumbents unchanged

The five pre-existing containers are `grid-minio`, `grid-core-n8n`,
`grid-core-n8n-worker`, `grid-postgres` and `grid-redis`. A GO-001
`faigrid-supervisor` container also runs on the daemon; it is not one of the five
and is not in scope here.

BEFORE and AFTER captures of `Id`, `State.StartedAt`, `RestartCount` and the
attached network set, taken over this lane's build/recreate cycle, are
byte-for-byte identical:

```
sha256 c8b9fb1b791635791bdcecdd915dd2823892e5ab0fadc34fd1b0bd958e96b51d  before
sha256 c8b9fb1b791635791bdcecdd915dd2823892e5ab0fadc34fd1b0bd958e96b51d  after
diff before after  ->  empty
```

All five remain `RestartCount=0` and attached **only** to `compose_grid_net`.
`compose_grid_net` was never inspected destructively, never pruned, never
touched: this lane creates one container on `faigrid_inference_net` and nothing
else. `grid-minio` carries no compose project label and was identified by name,
never by label.

## 8. The test and its red proof

`tests/integration/07-faigate-inference-reachability.bats` drives the docker
daemon on `nexus-core` through `docker -H ssh://nexus-core`, so no bats install is
needed on the node. Off that host, or with the daemon unreachable, the file
skips rather than failing a CI runner that has no substrate. Override the host
with `NEXUS_HOST`.

- **Red (gate absent):** `bats tests/integration/07-faigate-inference-reachability.bats`
  -> exit **1**, C1 and C2 fail with real assertion messages
  (`ASSERTION FAILED: curl could not run against faigate on faigrid_inference_net (exit 6): 000`),
  C3 still passes. Produced with `docker compose ... down` before the run.
- **Green (gate deployed):** same command -> exit **0**, 3/3 tests.

Adjusted expectations: none. Both runs are recorded with their exit codes in
this lane's report.

## 9. Operation and teardown

```bash
cd /home/nexus/faigate-inference
docker compose -f faigate-inference.yml up -d     # (re)start
docker compose -f faigate-inference.yml down      # remove the gate only
```

`down` removes only the `faigate-inference` project's container; the external
`faigrid_inference_net` is declared `external: true` and is never removed. This
lane never ran `docker system prune`, never `docker network prune`, and never
removed a tenant network.

## 10. What was deliberately NOT done

- No provider credential, `.env` or API key was written to the repository or to
  the node; `/v1/models` needs none.
- The five incumbents were not stopped, started, restarted or recreated; their
  compose definition (`external/compose/core-heart.reconstructed.yml`) and
  `/opt/faigrid/core-heart/.env` were not read for values and not modified.
- `compose_grid_net` was not modified or pruned.
- faigate's host configuration on the workstation was not copied to the node.
