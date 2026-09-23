# Step 11 — nexus-core core-heart workloads (reconstructed compose)

Scope: account for the five pre-existing containers on `nexus-core` that had run
for six months severed from their compose definition, and reconstruct a compose
file that makes the stack operable again — **without** touching a single running
container. This is lane **VT-001b** of sequence `veeona-tenant-substrate`, phase
0. It follows VT-001 (see `10-nexus-core-install.md`) and is serialized behind it
because both lanes share the live node.

Host: `nexus-core` (192.168.178.20, user `nexus`, key `~/.ssh/id_ed25519`).

## 1. The problem

The five running containers carried the label

```
com.docker.compose.project.config_files = /tmp/grid-install/core/heart/compose/docker-compose.yml
```

That path does not exist. The March 2026 install ran from a temp directory that
was cleaned up, so `docker compose down/up/update` were all severed from the
running state, and a docker daemon restart would have left the stack
unreconstructible from container labels and image digests alone.

This lane is **reconstruction, not redeployment**. The point is that the five
become operable again, not that they are restarted. A restart would retroactively
fail VT-001's criterion 3 and is the one thing this lane must not do.

## 2. Per-service accounting (criterion 1)

| Container | Disposition |
| --- | --- |
| `grid-core-n8n` | pre-existing, out of scope — reconstructed into compose, untouched |
| `grid-core-n8n-worker` | pre-existing, out of scope — reconstructed into compose, untouched |
| `grid-postgres` | pre-existing, out of scope — reconstructed into compose, untouched |
| `grid-redis` | pre-existing, out of scope — reconstructed into compose, untouched |
| `grid-minio` | pre-existing, out of scope — **not** a compose container; recorded, untouched |

Four of the five carry `com.docker.compose.*` labels and belong to the project
`compose`. `grid-minio` does **not** — it was started on 2026-09-08 via
`docker run` (no compose labels; its only labels are the image's own) and merely
joins the same network. Its volume `minio_data` also predates the project (no
compose labels, the others are `compose_{service}_data`). It is described in the
reconstructed file for completeness but is **not** managed by compose today, and
`docker compose ps` correctly does not list it.

## 3. What `docker inspect` established

| Field | Value |
| --- | --- |
| compose project | `compose` (label `com.docker.compose.project`) |
| compose version | `5.0.2` |
| environment file | `/opt/faigrid/core-heart/.env` (label `project.environment_file`) |
| network | `compose_grid_net`, bridge, non-internal; label `com.docker.compose.network=grid_net` |
| restart policy | `unless-stopped` on all five |
| volumes | `compose_postgres_data`, `compose_redis_data`, `compose_n8n_data` (compose-managed) + `minio_data` (external) |

Per container:

| Container | Image (digest) | command | key bind/mount | ports |
| --- | --- | --- | --- | --- |
| `grid-postgres` | `postgres:16` (`:ce5c12a…a63`) | `postgres` | `compose_postgres_data:/var/lib/postgresql/data` | — |
| `grid-redis` | `redis:7-alpine` (`:8b81dd3…065`) | `redis-server --appendonly yes` | `compose_redis_data:/data` | — |
| `grid-core-n8n` | `n8nio/n8n:latest` (`:1e764de…723`) | (entrypoint default) | `compose_n8n_data:/home/node/.n8n` | `127.0.0.1:5678→5678` |
| `grid-core-n8n-worker` | `n8nio/n8n:latest` (`:1e764de…723`) | `worker` | — | — |
| `grid-minio` | `minio/minio:latest` (`:14cea49…36e`) | `server /data --console-address :9001` | `minio_data:/data` | `9000→9000`, `9001→9001` |

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
   prepared for exactly this purpose.

They are identical in content. The node copy is the file operators actually use.

## 5. Secrets handling

The reconstruction contains **no secret value**. Every environment entry is an
interpolation reference into `/opt/faigrid/core-heart/.env` (the `--env-file`).
No value from that file was copied into the committed YAML — `docker compose
config` confirms the secrets resolve to values only at evaluation time on the
node (e.g. `DB_POSTGRESDB_PASSWORD`, `N8N_ENCRYPTION_KEY`,
`POSTGRES_PASSWORD`), never into the file itself.

Two references are **not** present in `.env` — `MINIO_ROOT_USER` and
`MINIO_ROOT_PASSWORD`. These exist only in the running `grid-minio` container.
The committed file references `${MINIO_ROOT_USER}` / `${MINIO_ROOT_PASSWORD}`
without a default, so `docker compose config` emits a "variable is not set"
warning. This is intentional and documented: it flags that whoever recreates the
stack must supply those two values, and it keeps the credentials out of any file
this lane owns. The `.env` itself (`root:root 644`) was not read for values,
not modified, and not copied into the repository.

## 6. What `docker compose` proves (criteria 2 and 3)

### 6.1 `config` resolves

```bash
docker compose --env-file /opt/faigrid/core-heart/.env \
  -f /opt/faigrid/core-heart/compose/docker-compose.yml config
```

exits 0. The resolved output names the project `compose`, the network
`compose_grid_net`, and the existing volumes (`compose_postgres_data`,
`compose_redis_data`, `compose_n8n_data`; `minio_data` as external).

### 6.2 `ps` recognises the project

```bash
cd /opt/faigrid/core-heart/compose
docker compose --env-file /opt/faigrid/core-heart/.env -f docker-compose.yml ps
```

reports the four compose-managed containers as `Up 6 months`, belonging to the
project `compose`:

```
NAME                   IMAGE                          SERVICE      STATUS       PORTS
grid-core-n8n          docker.n8n.io/n8nio/n8n:latest n8n          Up 6 months  127.0.0.1:5678->5678/tcp
grid-core-n8n-worker   docker.n8n.io/n8nio/n8n:latest n8n-worker   Up 6 months  5678/tcp
grid-postgres          postgres:16                     postgres     Up 6 months  5432/tcp
grid-redis             redis:7-alpine                  redis        Up 6 months  6379/tcp
```

The recognition relies on the project name `compose` (pinned via the top-level
`name:` key) and on matching `container_name`, image, ports, volumes and the
`condition: service_started` dependencies — which reproduce the running
containers' `com.docker.compose.*` labels exactly. `grid-minio` is absent from
this list because it is not a compose container.

## 7. Non-mutation proof

BEFORE and AFTER `docker inspect --format '{{.Id}} {{.Name}} {{.State.StartedAt}}
{{.RestartCount}}'` over `docker ps -q` are byte-for-byte identical
(`sha256 158dd9ff55aa649ea1808882a3971f8d8a5d36a779291e017b2d204d56d06cdf`).
No container was stopped, started, restarted or recreated. The only write this
lane made was the reconstructed YAML into the prepared `compose/` directory.

## 8. What was deliberately NOT done

- No `docker compose up/down/start/stop/restart` — reconstruction only.
- `/opt/faigrid/core-heart/.env` was not modified and its contents were not
  copied into anything committed.
- The minio credentials were not extracted from the running container into any
  file; they are left to be supplied at recreate time.
