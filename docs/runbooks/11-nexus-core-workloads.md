# Step 11 — nexus-core core-heart workloads (reconstructed compose)

Scope: account for the containers pre-existing on `nexus-core`, and reconstruct a
compose file that makes **faigrid's** core-heart stack operable again — **without**
touching a single running container. This is lane **VT-001b** of sequence
`veeona-tenant-substrate`, phase 0. It follows VT-001 (see
`10-nexus-core-install.md`) and is serialized behind it because both lanes share
the live node.

Host: `nexus-core` (192.168.178.20, user `nexus`, key `~/.ssh/id_ed25519`).

## 1. The problem

Four running containers carry the label

```
com.docker.compose.project.config_files = /tmp/grid-install/core/heart/compose/docker-compose.yml
```

That path does not exist. The March 2026 install ran from a temp directory that
was cleaned up, so `docker compose down/up/update` were all severed from the
running state, and a docker daemon restart would have left the stack
unreconstructible from container labels and image digests alone.

This lane is **reconstruction, not redeployment**. The point is that the four
become operable again, not that they are restarted. A restart would retroactively
fail VT-001's criterion 3 and is the one thing this lane must not do.

## 2. Per-service accounting: ownership (criterion 1)

Five containers run on the host. Four are faigrid's; the fifth is not, and the
distinction is ownership, not convenience.

| Container | Owner | Disposition |
| --- | --- | --- |
| `grid-core-n8n` | faigrid (core-heart compose project) | reconstructed into this file, untouched |
| `grid-core-n8n-worker` | faigrid (core-heart compose project) | reconstructed into this file, untouched |
| `grid-postgres` | faigrid (core-heart compose project) | reconstructed into this file, untouched |
| `grid-redis` | faigrid (core-heart compose project) | reconstructed into this file, untouched |
| `grid-minio` | **veeona** (tenant preliminary requirement) | **out of scope, not reconstructed**, untouched |

The four faigrid containers carry `com.docker.compose.*` labels and belong to the
project `compose`. `grid-minio` is veeona's object store: a preliminary
requirement of the tenant, deployed by veeona's own
`scripts/deploy_core_minio.sh` against `192.168.178.20:9000`, carrying buckets
`veeona-artifacts-dev` and `veeona-masters-dev`, and made the exclusive
cross-zone transfer path by veeona's **FND-006**. It carries zero
`com.docker.compose.*` labels, was started 2026-09-08 (`docker run`, five months
after the other four), and joins `compose_grid_net` only incidentally as a
co-tenant of the host. Its volume `minio_data` likewise predates and does not
belong to the compose project (the project's own volumes are
`compose_{service}_data`).

`grid-minio` is therefore **absent from the reconstructed file by ownership**:
not as a service, not as a commented-out block, and not as a variable reference.
Its root credentials are set in veeona's `deploy_core_minio.sh`; they are not
faigrid's to hold and are not in faigrid's `.env`. A `${MINIO_ROOT_*}` reference
from a faigrid file would silently resolve to an empty string with exit 0 — the
exact degradation this lane exists to remove — so no such reference remains.

`docker compose ps` lists exactly the four; `grid-minio` is absent because it is
not a compose container, and cannot be made to appear without recreating it,
which this lane must not do.

## 3. What `docker inspect` established

| Field | Value |
| --- | --- |
| compose project | `compose` (label `com.docker.compose.project`) |
| compose version | `5.0.2` |
| environment file | `/opt/faigrid/core-heart/.env` (label `project.environment_file`) |
| network | `compose_grid_net`, bridge, non-internal; label `com.docker.compose.network=grid_net` |
| restart policy | `unless-stopped` on all four |
| volumes | `compose_postgres_data`, `compose_redis_data`, `compose_n8n_data` (compose-managed) |

Per container:

| Container | Image (digest) | command | key bind/mount | ports |
| --- | --- | --- | --- | --- |
| `grid-postgres` | `postgres:16` (`:ce5c12a…a63`) | `postgres` | `compose_postgres_data:/var/lib/postgresql/data` | — |
| `grid-redis` | `redis:7-alpine` (`:8b81dd3…065`) | `redis-server --appendonly yes` | `compose_redis_data:/data` | — |
| `grid-core-n8n` | `n8nio/n8n:latest` (`:1e764de…723`) | (entrypoint default) | `compose_n8n_data:/home/node/.n8n` | `127.0.0.1:5678→5678` |
| `grid-core-n8n-worker` | `n8nio/n8n:latest` (`:1e764de…723`) | `worker` | — | — |

`com.docker.compose.depends_on` on the n8n containers records
`postgres:service_started:false` and `redis:service_started:false`, i.e. a
`condition: service_started` short-form dependency (`required: false`).

## 4. The reconstructed file

The reconstruction lives in two places:

1. **Repo copy (committed, secret-free):**
   `external/compose/core-heart.reconstructed.yml`.
2. **Node copy (the durable operand, written by this lane, NOT committed):**
   `/opt/faigrid/core-heart/compose/docker-compose.yml` — the
   `compose/` directory under `/opt/faigrid/core-heart` that the operator
   prepared for exactly this purpose. `nexus:nexus`, mode 644.

They are byte-identical (sha256
`d3f40dc98fb010bda841448be3721dec5fa067ea7ba6fbadfb32ef552d82717b`). The node
copy is the file operators actually use.

## 5. Secrets handling

The reconstruction contains **no secret value**. Every environment entry is an
interpolation reference into `/opt/faigrid/core-heart/.env` (the `--env-file`).
No value from that file was copied into the committed YAML — `docker compose
config` resolves the secrets to values only at evaluation time on the node
(e.g. `DB_POSTGRESDB_PASSWORD`, `N8N_ENCRYPTION_KEY`, `POSTGRES_PASSWORD`),
never into the file itself.

Every reference in the file is satisfied by `.env`: the file resolves with an
**empty stderr** (see §6.1). The `.env` itself (`root:root 644`, mtime
2026-03-25, predating this lane) was not read for values, not modified, and not
copied into the repository.

## 6. What `docker compose` proves (criteria 2 and 3)

### 6.1 `config` resolves with no warning

```bash
docker compose --env-file /opt/faigrid/core-heart/.env \
  -f /opt/faigrid/core-heart/compose/docker-compose.yml config
```

- exit **0**
- **stderr: empty (0 bytes)** — no `variable is not set` warning of any kind
- stdout names the project `compose`, the network `compose_grid_net`, and the
  existing volumes (`compose_postgres_data`, `compose_redis_data`,
  `compose_n8n_data`); it contains no minio reference

An empty stderr is the proof; exit 0 alone is not — a missing variable warns and
defaults to `""` while still exiting 0, which is how the previous revision
degraded silently.

### 6.2 `ps` recognises exactly the four project containers

```bash
cd /opt/faigrid/core-heart/compose
docker compose --env-file /opt/faigrid/core-heart/.env -f docker-compose.yml ps
```

```
NAME                   IMAGE                            COMMAND                  SERVICE      CREATED        STATUS        PORTS
grid-core-n8n          docker.n8n.io/n8nio/n8n:latest   "tini -- /docker-ent…"   n8n          6 months ago   Up 6 months   127.0.0.1:5678->5678/tcp
grid-core-n8n-worker   docker.n8n.io/n8nio/n8n:latest   "tini -- /docker-ent…"   n8n-worker   6 months ago   Up 6 months   5678/tcp
grid-postgres          postgres:16                      "docker-entrypoint.s…"   postgres     6 months ago   Up 6 months   5432/tcp
grid-redis             redis:7-alpine                   "docker-entrypoint.s…"   redis        6 months ago   Up 6 months   6379/tcp
```

Four rows — exactly the project containers, `ps -a` likewise returns four names
and no more. The recognition relies on the project name `compose` (pinned via
the top-level `name:` key) and on matching `container_name`, image, ports,
volumes and the `condition: service_started` dependencies — which reproduce the
running containers' `com.docker.compose.*` labels. `grid-minio` is absent
because it is veeona's `docker run` container, not a compose container.

## 7. Non-mutation proof

BEFORE and AFTER `docker inspect --format '{{.Id}} {{.Name}} {{.State.StartedAt}}
{{.RestartCount}}'` over `docker ps -q` are byte-for-byte identical
(`sha256 158dd9ff55aa649ea1808882a3971f8d8a5d36a779291e017b2d204d56d06cdf`).
All five containers, `grid-minio` included, are `RestartCount=0`. No container
was stopped, started, restarted or recreated. The only write this lane made was
the reconstructed YAML into the prepared `compose/` directory.

## 8. What was deliberately NOT done

- No `docker compose up/down/start/stop/restart` — reconstruction only.
- `grid-minio` was not reconstructed, not restarted, not stopped, not adopted,
  and no reference to its credentials was written into any faigrid file.
- `/opt/faigrid/core-heart/.env` was not modified and its contents were not
  copied into anything committed.

## 9. Preflight verification against the live substrate (GO-005)

`core/tenant/preflight.sh` validates the tenant substrate before any tenant
workload spawns. It checks that both external tenant networks
(`faigrid_control_net`, `faigrid_inference_net`) are present, use the `bridge`
driver, carry the faigrid creator label, and have at least one IPAM subnet.

The integration test `tests/integration/08-preflight-live-substrate.bats`
proves three criteria against the live nexus-core docker daemon:

| Criterion | Proof |
| --- | --- |
| C1 | `preflight.sh` returns exit 0 against the live substrate |
| C2 | With one tenant network removed, it refuses BY NAME and creates nothing — `docker ps -a` is identical before and after, and the network is restored |
| C3 | The refusal precedes any tenant container creation — no container with the `faigrid-tenant-*` prefix ever existed |

**How it runs:** the test addresses the nexus-core daemon via
`docker -H ssh://nexus-core`, so no bats installation is needed on the node.
The test removes `faigrid_inference_net` (disconnecting the faigate container
first), runs preflight to confirm the refusal, restores the network and
reconnects faigate, then verifies preflight passes again. `compose_grid_net`
and the five incumbent containers are never touched.

**Red proof:** the C2+C3 test exits 1 if preflight passes with a network
missing — a guard against regressions that would silently authorise an
incomplete substrate.

**Node state note:** `/opt/faigrid-src/core/tenant/*.sh` are byte-identical to
v1.9.0 (all five sha256 match, measured 2026-09-24) while `VERSION` and
`~/.config/faigrid/registry/state.env` both read 1.8.0. That metadata mismatch
is a known defect (same class as LVC-268) and is not resolved by this lane.
