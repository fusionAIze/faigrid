# Step 10 — faigrid substrate on nexus-core (provisional install)

Scope: bring the `faigrid` command onto `nexus-core` durably, record the install
in the node registry, and prove that no running service was restarted or
reconfigured in the process. This is lane **VT-001** of sequence
`veeona-tenant-substrate`, phase 0.

Host: `nexus-core` (192.168.178.20, user `nexus`, key `~/.ssh/id_ed25519`),
Linux 6.12.63+deb13-amd64.

> **This arrangement is PROVISIONAL.** It is a hand-execution of the contract
> that **FAI-233** will automate. It is **not** the intended long-term path.
> See §7.

## 1. The problem this runbook works around

`install.sh` has no `--prefix` and installs nothing of itself. A `git clone`
therefore never yields the `faigrid` command that `install.sh --help` advertises
— only the Homebrew formula installs a `faigrid` shim, and Homebrew is the
workstation channel, not a Debian server channel. Until FAI-233 gives
`install.sh` a prefix and a shim, the two root-owned pieces below are created by
hand.

The lane has **no root**. The two root-owned pieces are created by the operator,
in parallel with this run; the lane only populates the nexus-owned checkout and
verifies the result.

## 2. The provisional arrangement (operator decision 2026-09-23)

| Piece | Path | Owner | Created by |
| --- | --- | --- | --- |
| Durability anchor (durable checkout) | `/opt/faigrid-src` | `nexus:nexus` | operator (root) |
| CLI shim | `/usr/local/bin/faigrid` | `root:root`, mode `0755` | operator (root) |

The shim is exactly:

```sh
#!/bin/sh
exec bash /opt/faigrid-src/install.sh "$@"
```

`/usr/local/bin` is chosen because it is on the non-interactive SSH `PATH`
(`/usr/local/bin:/usr/bin:/bin:/usr/games`); `~/.local/bin` is **not**. The
checkout lives at a durable path because the entrypoint resolves `REPO_ROOT`
from its own location (`install.sh:56`), so it works from any path — including
this one, after `/tmp` is gone.

## 3. Commands run, in order (copy-pasteable)

All commands were run from the lane workstation against `nexus-core`. The
before/after docker captures were written to `/tmp/vt001-*.txt` on the node.

### 3.0 Connectivity

```bash
ssh -o BatchMode=yes nexus-core 'echo CONNECTED; hostname -s; uname -s; echo "PATH=$PATH"; id -un'
```

### 3.1 Capture BEFORE state (criterion 3)

```bash
ssh -o BatchMode=yes nexus-core \
  'docker inspect --format "{{.Id}} {{.Name}} {{.State.StartedAt}} {{.RestartCount}}" $(docker ps -q)' \
  > /tmp/vt001-before.txt
```

### 3.2 Red proof (before install)

```bash
ssh -o BatchMode=yes nexus-core 'command -v faigrid'                                # exit 1, no output
ssh -o BatchMode=yes nexus-core 'faigrid --status'                                  # exit 127, command not found
ssh -o BatchMode=yes nexus-core 'cat ~/.config/faigrid/registry/state.env'          # GRID_VERSION=latest, INSTALL_DATE 24 March 2026
ssh -o BatchMode=yes nexus-core 'ls -ld /opt/faigrid-src /usr/local/bin/faigrid'    # both no such file
```

### 3.3 Wait for the two root-owned pieces (no root in this lane)

Polled `ls -ld /opt/faigrid-src` and `ls -l /usr/local/bin/faigrid` until both
appeared. Both were created by the operator at `21:13`. Nothing was created,
moved or chmodded by this lane.

```bash
ls -ld /opt/faigrid-src          # drwxr-xr-x nexus:nexus
cat /usr/local/bin/faigrid       # #!/bin/sh / exec bash /opt/faigrid-src/install.sh "$@"
stat -c "%A %U:%G %n" /usr/local/bin/faigrid   # -rwxr-xr-x root:root
```

### 3.4 Populate the durable checkout

```bash
rsync -az --delete --exclude='.git' --exclude='node_modules' ./ nexus-core:/opt/faigrid-src/
```

### 3.5 Criterion 1 — the command runs on the node

```bash
ssh -o BatchMode=yes nexus-core 'command -v faigrid'   # /usr/local/bin/faigrid
ssh -o BatchMode=yes nexus-core 'faigrid --status'     # exit 0, prints Node Status v1.8.0
```

### 3.6 Criterion 2 — record this install in the registry

The installer's own registration path (it runs no install scripts and touches
no service):

```bash
cd /opt/faigrid-src && bash install.sh --mode local --role core --bootstrap </dev/null
```

`install.sh` hard-codes `GRID_VERSION=latest` in `write_state()`
(`install.sh:314,325,332`), so the version field is then set to the installed
version by hand — the one step FAI-233 must automate:

```bash
VERSION=$(cat /opt/faigrid-src/VERSION)
sed -i "s/^GRID_VERSION=.*/GRID_VERSION=${VERSION}/" \
  ~/.config/faigrid/registry/state.env \
  ~/.config/faigrid/registry/core.state
```

### 3.7 Capture AFTER state (criterion 3)

```bash
ssh -o BatchMode=yes nexus-core \
  'docker inspect --format "{{.Id}} {{.Name}} {{.State.StartedAt}} {{.RestartCount}}" $(docker ps -q)' \
  > /tmp/vt001-after.txt
```

## 4. Evidence — criterion 1

Exact command, non-interactive SSH session (ANSI colour codes stripped for
readability; the banner is coloured on the wire):

```console
$ ssh nexus-core faigrid --status
  Node Status  v1.8.0 · nexus-core · linux
  ──────────────────────────────────────
  SERVICE         PORT    STATUS
  ──────────────────────────────────────
  messenger       9119    ✘ stopped
  n8n             5678    ✔ running
  faigate         8090    ✘ stopped
  openclaw        18789   ✔ running
  ──────────────────────────────────────
exit=0
```

The version comes from `/opt/faigrid-src/VERSION` (`1.8.0`). `command -v
faigrid` resolves to `/usr/local/bin/faigrid`.

## 5. Evidence — criterion 2

`~/.config/faigrid/registry/state.env` **after** the install:

```console
GRID_ROLE=core
GRID_VERSION=1.8.0
INSTALL_DATE="Mi 23. Sep 21:14:10 CEST 2026"
```

- `GRID_VERSION=1.8.0` — not the literal string `latest`; equal to the
  installed `VERSION`.
- `INSTALL_DATE` is from **this** install (`23. Sep 2026`, 21:14 CEST), not the
  migrated `24 March 2026` value.

The sibling registry file `~/.config/faigrid/registry/core.state` was corrected
the same way and carries the same role, version and date, plus `EXEC_MODE=local`.

## 6. Evidence — criterion 3 (non-mutation)

BEFORE (`/tmp/vt001-before.txt`) and AFTER (`/tmp/vt001-after.txt`) are
byte-for-byte identical; `sha256 = 158dd9ff55aa649ea1808882a3971f8d8a5d36a779291e017b2d204d56d06cdf`.

```console
64b5dce26c0f4c033e269218dbac823b2a8c1cf82a7bfa838683e3126e4a72da /grid-minio 2026-09-08T12:35:56.907641619Z 0
77f942edb0881eada3dac90130afaf005fb961914bb1674c0e447dc78afada19 /grid-core-n8n 2026-03-25T14:22:15.714092611Z 0
ad724c80d9c9cbf40c7a076cc23b3c656091842560de63a025172d070259f01c /grid-core-n8n-worker 2026-03-25T14:22:15.709124535Z 0
062269515ab9cc68a08e52aa0877e0deece990f46eedafa1cee547369eaa7b94 /grid-postgres 2026-03-25T14:22:15.533272427Z 0
8fda6e65fbedcc528a61c2c89a7f4893dbe5e438e27340995afd8226d55bc286 /grid-redis 2026-03-25T13:26:52.375744441Z 0
```

Every container ID, `StartedAt` and `RestartCount` is unchanged; all
`RestartCount=0`. No `docker compose up`, no restart, no recreate.

```console
$ docker ps --format '{{.ID}} {{.Names}} {{.RunningFor}}'
64b5dce26c0f grid-minio 2 weeks ago
77f942edb088 grid-core-n8n 6 months ago
ad724c80d9c9 grid-core-n8n-worker 6 months ago
062269515ab9 grid-postgres 6 months ago
8fda6e65fbed grid-redis 6 months ago
```

## 7. Provisional status — pending FAI-233

This section exists because the arrangement in §2 is **not** the intended path.

- `faigrid` is a shim at `/usr/local/bin/faigrid` that `exec`s a durable
  checkout at `/opt/faigrid-src`. Both pieces were created **by hand**, by the
  operator, because `install.sh` installs nothing of itself.
- The registry version field was set by hand because `write_state()` hard-codes
  `GRID_VERSION=latest` (`install.sh:314,325,332`). Criterion 2 requires a
  version that is not the literal string `latest`; the hand-correction records
  the actual installed `VERSION`.
- **FAI-233 must automate both**: give `install.sh` a prefix and install its own
  `faigrid` shim, and record the real installed version in `state.env` instead
  of the literal `latest`. When FAI-233 lands, this runbook is superseded and
  the hand steps in §3.3 and §3.6 are removed.
- No service was deployed by this lane. The five running containers predate the
  work; they are **not** adopted here and are **out of scope** for VT-001
  (they are VT-001b's subject). Only two containers respond on the status ports
  (`n8n` on 5678, `openclaw` on 18789) — untouched.

## 8. Per-service accounting

| Container | State | Disposition |
| --- | --- | --- |
| `grid-core-n8n` | running, `RestartCount=0` | pre-existing, out of scope — untouched |
| `grid-core-n8n-worker` | running, `RestartCount=0` | pre-existing, out of scope — untouched |
| `grid-postgres` | running, `RestartCount=0` | pre-existing, out of scope — untouched |
| `grid-redis` | running, `RestartCount=0` | pre-existing, out of scope — untouched |
| `grid-minio` | running, `RestartCount=0` | pre-existing, out of scope — untouched |

## 9. What was deliberately NOT done

- `core/heart/scripts/install.sh` (the root deploy path) was **not** run. It
  requires `sudo` (no passwordless sudo on this node) and ends in
  `docker compose up -d`, which would restart the five running containers and
  fail criterion 3.
- `~/.grid-state` was **not** hand-migrated. `migrate_1.3.sh` owns that path and
  is FAI-230's subject. The migration had already happened before this lane.
- `/opt/faigrid` (the five sibling project directories) was **not** touched;
  that tree belongs to VT-001b.
