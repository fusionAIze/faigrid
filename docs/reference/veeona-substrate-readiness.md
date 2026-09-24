# veeona substrate readiness — VT-007

**Lane:** VT-007, sequence `veeona-tenant-substrate`, phase 3
**Branch:** `ops/vt-VT-007` · **Base:** `6699538` (`origin/main`)
**Measured on:** `nexus-core` (192.168.178.20, user `nexus`), 2026-09-24
**Verdict:** **not ready to start veeona**, and honestly so. Criterion 1 (the
two external networks resolve) is **met**. The substrate below the tenant is in
place; what remains is the operator's call to start veeona, which this lane does
not take.

This report states, per handover clause, **met / not met / out of scope**. No
clause is left unaddressed. This lane reports the truth about the substrate; it
does not make the substrate true.

## 1. Provenance of the clause list

The handover of 2026-09-22 is the authority for the clause numbering (PRD
`prd.md` §2, VT-003 description: "Handover clause 5"). The handover document
itself is **not present** in any checkout reachable from this lane: it is not in
`fusionaize-planning` history (`git log --all -- '*discovery*'` finds no
veeona-tenant discovery or handover file) and not in the `veeona` repository.
What *is* durable is the PRD executive summary, which restates the contract as
"the five obligations veeona's handover contracts for", and the two clauses the
tasks quote by number (VT-003: clause 5, both external networks provisioned and
healthy before tenant workloads spawn).

The clause list below is therefore grounded on the authoritative PRD obligations
and the quoted clause 5. **If the reviewer holds the original handover and its
numbering differs, that is a finding against this report's numbering, not
against its measurements.**

## 2. Handover clauses — verdicts

| Clause | Obligation (authoritative source) | Verdict | Evidence |
|---|---|---|---|
| HC-1 | Tenant network isolation exists and is never bridged (SEC-001; PRD §5 VT-002, §8) | met | `faigrid_control_net` and `faigrid_inference_net` exist on the node, both carry `com.fusionaize.faigrid.creator=faigrid`, created by `core/tenant/networks.sh`. Isolation proven by a refused connection in `tests/integration/03-tenant-network-isolation.bats` (C3): a container on inference_net cannot reach one on control_net. |
| HC-2 | A preflight refuses a tenant start on an unready substrate (PRD §5 VT-003) | met | `core/tenant/preflight.sh` + `tests/unit/06-tenant-preflight.bats`. With either network absent it refuses by name and creates nothing (`docker ps -a` diff empty). |
| HC-3 | Tenant requests are routed and cost is attributable to `veeona-hq`; no silent attribution (FND-003; PRD §5 VT-004) | met | `core/tenant/routing.sh` + `tests/unit/07-tenant-routing.bats`. A request carrying `FAIGRID_ORG_ID=veeona-hq` and `X-Tenant-ID` is routed and recorded; an untagged request is refused/explicitly defaulted, never silently attributed. |
| HC-4 | One dual-homed mediator, IP forwarding off, no long-lived secret in any worker (D2; PRD §5 VT-005) | met | `core/tenant/credential-mediator.sh` + `tests/integration/04-mediator-isolation.bats`. Exactly one container is dual-homed; a forward attempt through it is refused; no long-lived secret is present in a worker environment. |
| HC-5 | Both external networks are provisioned and healthy **before** tenant workloads spawn (quoted clause; PRD §5 VT-003, VT-007) | met | This lane created both networks on the node through faigrid's code path and proved both resolve. The preflight (HC-2) gates the spawn on the same two networks. Nothing was started. |
| HC-6 | A recovery journal preserving `correlation_id` that veeona can poll (D3; PRD §5 VT-006) | met | `core/tenant/recovery-journal.sh` + `tests/unit/08-recovery-journal.bats`. A worker restart appends a `FaiGridRecoveryEvent` with the original `correlation_id`; the write position is exposed for veeona's cursor; with the webhook unreachable the event is still recorded and the job continues. |
| HC-7 | veeona is a nested tenant, not a co-resident of the flat bridge (PRD §2, §7) | **not met** | veeona's compose attaches z0 to `faigrid_control_net` and z1/z2 to `faigrid_inference_net`, and this lane proved those resolve. But the tenant is **not started**: no network attachment exists yet, and the incumbent five services remain on `compose_grid_net` (explicitly out of scope, PRD §11). The nesting becomes real only when the operator starts veeona. |
| HC-8 | The five pre-existing workloads are undisturbed and operable (VT-001b; PRD §11 risk) | met | Container IDs, `StartedAt` and `RestartCount` of all five are byte-identical before and after this lane; `compose_grid_net` is unchanged. Ownership: four are faigrid core-heart, `grid-minio` is veeona's object store (VT-001b). |
| HC-9 | Start veeona itself | **out of scope** | PRD §9: "Out: starting veeona (the operator's call, and only after the readiness report)". This lane deliberately starts nothing. |
| HC-10 | Hermes agent / PRT-008 end to end | **out of scope** | PRD §9; separate round (PRT-008 carries its own 32-point PRD). |

Every clause above carries one of **met / not met / out of scope**. None is
unaddressed. HC-7 is the only **not met**, and it is honestly not met: the
substrate is ready, the tenant is not started. That is the permitted outcome.

## 3. Measurements (criterion 1 and the red proof)

All commands were run on `nexus-core` over SSH as `nexus`. `docker compose
config` is read-only; nothing was started, stopped, restarted or recreated.

### 3.1 Red proof (a) — recorded starting state, before creation

Measured 2026-09-24, before this lane created anything:

```
$ ssh nexus-core "docker network ls"
NETWORK ID     NAME               DRIVER    SCOPE
9dd03479fb0d   bridge             bridge    local
7cc1df38efc2   compose_grid_net   bridge    local
164cfac43596   host               host      local
09fd5857543e   none               null      local

$ ssh nexus-core "docker network inspect faigrid_control_net >/dev/null 2>&1"; echo $?
1
$ ssh nexus-core "docker network inspect faigrid_inference_net >/dev/null 2>&1"; echo $?
1
```

Both tenant networks were absent, so neither external network resolved. This is
the state criterion 1 is measured against.

**A finding about `docker compose config`.** The lane brief and the sequence's
red proof expect `docker compose config` to **fail** when the external networks
are absent. On this node (Docker Compose **v5.0.2**) it does **not**:

```
$ ssh nexus-core "cd /tmp/vt007-veeona && docker compose --profile all config"; echo $?
... (renders the full config, external: true names intact) ...
0
```

Compose v5 resolves the external network **name** from the file and does not
contact the daemon to assert the network exists. A validation that asserts only
the `config` exit code would therefore be **green on an unready substrate** —
the exact false-positive this lane exists to prevent. The resolvable proof used
here is: render the config, parse the external networks out of it, then
`docker network inspect` each one. That is read-only and it *does* fail when a
network is absent.

### 3.2 Creation through faigrid's own code path

The two networks were created by `core/tenant/networks.sh` (merged at `6699538`),
copied to `/tmp/vt007-faigrid/core/tenant/networks.sh` on the node. No
hand-written `docker network create` was used.

```
$ ssh nexus-core "cd /tmp/vt007-faigrid && bash core/tenant/networks.sh create"
[INFO] created tenant network 'faigrid_control_net'
[INFO] created tenant network 'faigrid_inference_net'
$ echo $?
0
```

Creator label read back from both networks:

```
$ ssh nexus-core "docker network inspect -f '{{index .Labels \"com.fusionaize.faigrid.creator\"}}' faigrid_control_net"
faigrid
$ ssh nexus-core "docker network inspect -f '{{index .Labels \"com.fusionaize.faigrid.creator\"}}' faigrid_inference_net"
faigrid
```

### 3.3 Criterion 1 — both external networks resolve

```
$ ssh nexus-core "docker network inspect faigrid_control_net  >/dev/null 2>&1"; echo $?
0
$ ssh nexus-core "docker network inspect faigrid_inference_net >/dev/null 2>&1"; echo $?
0
$ ssh nexus-core "cd /tmp/vt007-veeona && docker compose --profile all config >/dev/null 2>&1"; echo $?
0
```

`docker network ls` after creation:

```
NETWORK ID     NAME                    DRIVER    SCOPE
9dd03479fb0d   bridge                  bridge    local
7cc1df38efc2   compose_grid_net        bridge    local
fab198ac103a   faigrid_control_net     bridge    local
354857016a87   faigrid_inference_net   bridge    local
164cfac43596   host                    host      local
09fd5857543e   none                    null      local
```

### 3.4 Red proof (b) — remove one network, show the failure, restore it

`faigrid_inference_net` was removed through the faigrid code path
(`faigrid_net_remove`, which honours the creator label), then the resolution
check was re-run, then the network was recreated:

```
$ ssh nexus-core "cd /tmp/vt007-faigrid && bash -c 'source core/tenant/networks.sh; faigrid_net_remove faigrid_inference_net'"
[INFO] removed tenant network 'faigrid_inference_net'

$ ssh nexus-core "docker network inspect faigrid_control_net  >/dev/null 2>&1"; echo $?
0
$ ssh nexus-core "docker network inspect faigrid_inference_net >/dev/null 2>&1"; echo $?
1        # <- the unresolved network, named

$ ssh nexus-core "cd /tmp/vt007-faigrid && bash core/tenant/networks.sh create"
[INFO] tenant network 'faigrid_control_net' already exists; leaving it in place
[INFO] created tenant network 'faigrid_inference_net'
$ echo $?
0

$ ssh nexus-core "docker network inspect faigrid_inference_net >/dev/null 2>&1"; echo $?
0
```

### 3.5 Criterion 2 — no veeona container, asserted

```
$ ssh nexus-core "docker ps --format '{{.Names}}'"
grid-minio
grid-core-n8n
grid-core-n8n-worker
grid-postgres
grid-redis

$ ssh nexus-core "docker ps --format '{{.Names}}' | grep -c veeona || true"
0
```

None of veeona's declared `container_name`s
(`veeona-grid-edge`, `veeona-z0-control`, `veeona-z1-research`,
`veeona-z2-production`, `veeona-knowledge-graph`) is running. The bats test
asserts this, it does not observe it in passing.

### 3.6 Non-mutation of `compose_grid_net` and the five incumbents

`compose_grid_net` inspect is byte-identical before and after
(`sha256 906a3b8edb8c1cab95b1bb1e41bb3d0ac3d5ce5ec6cdafb7a86ace4c62c91ffa` both
times). The five containers' `Id StartedAt RestartCount` before and after are
identical (empty `diff`):

```
64b5dce26c0f... /grid-minio          2026-09-08T12:35:56.907641619Z 0
77f942edb088... /grid-core-n8n       2026-03-25T14:22:15.714092611Z 0
ad724c80d9c9... /grid-core-n8n-worker 2026-03-25T14:22:15.709124535Z 0
062269515ab9... /grid-postgres       2026-03-25T14:22:15.533272427Z 0
8fda6e65fbed... /grid-redis          2026-03-25T13:26:52.375744441Z 0
```

No container gained or lost a network attachment.

## 4. Criterion 3 — this report

The test `tests/integration/05-substrate-readiness.bats` C3 asserts this file
exists, that it carries at least five `HC-` clause rows, and that every clause
row also carries a `met` / `not met` / `out of scope` verdict — so an
unaddressed clause fails the suite.

## 5. What is NOT claimed

- This lane does **not** claim veeona is hosted, started or running.
- This lane does **not** claim the incumbent five services are migrated off
  `compose_grid_net`; they are not, and that is out of scope (PRD §11).
- This lane does **not** claim the handover clause numbering in §2 is verbatim
  the original handover's; it is grounded on the authoritative PRD obligations
  and the quoted clause 5, and the provenance gap is named in §1.
- HC-7 is **not met**, and is reported as such rather than papered over.
