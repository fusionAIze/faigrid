# Step 12 — Supervisor Control API (GO-001)

Scope: Build and verify the faigrid Supervisor and its Control API on `nexus-core`,
presenting Scheduler, Runner Pool and Recovery Engine through the surface veeona
calls: register(), poll(), recovery_history(job_id) and max_workers.

Host: `nexus-core` (192.168.178.20, user `nexus`, key `~/.ssh/id_ed25519`).

## 1. Operator decision D5

Supervisor becomes the stack's umbrella term for the faigrid service that presents
Scheduler, Runner Pool and Recovery Engine through the Control API. It is an
addition to the vocabulary, not a competing concept. veeona's
`FAIGRID_SUPERVISOR_URL` stays as it is.

## 2. The API surface

| Method | Endpoint | Description |
| --- | --- | --- |
| POST | `/v1/supervisor/register` | Register a worker |
| GET | `/v1/supervisor/poll` | Poll for status |
| GET | `/v1/supervisor/recovery_history/{job_id}` | Read recovery journal entries for a worker |
| GET | `/v1/supervisor/max_workers` | Return max worker count |

## 3. Network topology

The Supervisor container is attached **only** to `faigrid_control_net`. It is
never attached to `faigrid_inference_net`. This preserves SEC-001: the control
plane and inference plane remain isolated.

| Network | Supervisor reachable? | Evidence |
| --- | --- | --- |
| `faigrid_control_net` | Yes (200) | `docker run --rm --net faigrid_control_net busybox wget -q -O /dev/null http://faigrid-core:5000/v1/supervisor/max_workers` |
| `faigrid_inference_net` | **Refused** | Same probe from `faigrid_inference_net` — timeout or connection refused |

## 4. Files

| File | Purpose |
| --- | --- |
| `core/supervisor/supervisor.sh` | Bash orchestration library (start, stop, probe, wait) |
| `core/supervisor/control-api.sh` | Inline Python stdlib HTTP server |
| `tests/unit/09-supervisor-control-api.bats` | Unit tests |
| `docs/runbooks/12-supervisor-control-api.md` | This runbook |

### 4.1 Idiom

Follows the credential-mediator idiom from `core/tenant/credential-mediator.sh`:
inline `python3 -c` with stdlib `http.server`, so the test never depends on a
bind-mount for the server code. The recovery journal directory IS bind-mounted
(read-only) so the Python process inside the container can read journal entries.

## 5. Deploy and verify

### 5.1 BEFORE capture

```bash
ssh nexus-core "
  docker ps --format '{{.ID}} {{.Names}} {{.CreatedAt}} {{.Status}}' > /tmp/go001-before.txt
  for cid in \$(docker ps -q); do
    docker inspect -f '{{.Id}} {{.State.StartedAt}} {{.RestartCount}}' \"\$cid\" >> /tmp/go001-before-inspect.txt
  done
"
```

### 5.2 Start the supervisor

```bash
ssh nexus-core "
  cd /opt/faigrid-src
  source core/supervisor/supervisor.sh
  faigrid_supervisor_start faigrid_control_net
  faigrid_supervisor_wait_ready faigrid_control_net
"
```

### 5.3 Probe from control_net

```bash
ssh nexus-core "
  docker run --rm --network faigrid_control_net busybox \
    wget -q -O - http://faigrid-core:5000/v1/supervisor/max_workers
  docker run --rm --network faigrid_control_net busybox \
    wget -q -O - --header 'Content-Type: application/json' \
    --post-data '{\"worker\":\"z1-7\"}' \
    http://faigrid-core:5000/v1/supervisor/register
  docker run --rm --network faigrid_control_net busybox \
    wget -q -O - http://faigrid-core:5000/v1/supervisor/poll
"
```

### 5.4 Counter-probe from inference_net (must be refused)

```bash
ssh nexus-core "
  # This MUST fail with a timeout or connection refused
  docker run --rm --network faigrid_inference_net busybox \
    wget -q -T 3 -O /dev/null http://faigrid-core:5000/v1/supervisor/max_workers && \
    echo 'SEC-001 VIOLATION: supervisor answered from inference_net' || \
    echo 'OK: refused as expected'
"
```

### 5.5 recovery_history

```bash
ssh nexus-core "
  # Write a journal entry
  source core/tenant/recovery-journal.sh
  recovery_journal_record_job 'z1-7' 'corr-demo-001'
  recovery_journal_append 'z1-7' 'corr-demo-001' 'restart' '1'

  # Read it back through the API
  docker run --rm --network faigrid_control_net busybox \
    wget -q -O - http://faigrid-core:5000/v1/supervisor/recovery_history/z1-7
"
```

### 5.6 AFTER capture

```bash
ssh nexus-core "
  for cid in \$(docker ps -q); do
    docker inspect -f '{{.Id}} {{.State.StartedAt}} {{.RestartCount}}' \"\$cid\"
  done
"
```

Compare BEFORE and AFTER: Id, StartedAt and RestartCount must be identical for
all five incumbent containers (grid-minio, grid-core-n8n, grid-core-n8n-worker,
grid-postgres, grid-redis).

## 6. Recovery journal contract

`recovery_history` reads the journal file at
`/var/lib/faigrid/recovery/recovery.jsonl`, which
`core/tenant/recovery-journal.sh` writes. It:

- Filters by worker (`job_id` parameter) — exact string match on the `worker`
  field of each JSONL record
- Preserves `correlation_id` verbatim — the same literal string written by
  `recovery_journal_record_job()` or `recovery_journal_append()`
- Does NOT write to the journal, create position files, or introduce any
  parallel record of the same events
- Returns `{"worker":"<job_id>","entries":[...]}` — the entries array contains
  every matching record from the journal

## 7. Tests

```bash
cd /opt/faigrid-src
bats tests/unit/09-supervisor-control-api.bats
```

Expected: all tests pass.

**RED PROOF**: with `--network faigrid_control_net` removed from the
`docker run` in `faigrid_supervisor_start`, test C1a exits 1 with a real
assertion message about the probe failing.
