# Event schema

`log_event()` in `core/workbench/scripts/_lib.sh` writes structured events as
JSONL — one JSON object per line — to two files:

- `/var/log/faigrid/grid-system.log`
- `/var/log/faigrid/grid-events.jsonl`

## Format

Each line is a single JSON object, no trailing comma:

```json
{"ts":"2026-08-22T00:00:00Z","component":"system","severity":"INFO","message":"..."}
```

## Fields

| Field       | Type   | Description                                            |
| ----------- | ------ | ------------------------------------------------------ |
| `ts`        | string | UTC ISO-8601 timestamp (`date -u +"%Y-%m-%dT%H:%M:%SZ"`) |
| `component` | string | Emitting component (e.g. `system`, `watchdog`)         |
| `severity`  | string | Severity level (see below)                             |
| `message`   | string | Free-form message, JSON-escaped                        |

The `message` field has `"`, `\`, and control characters escaped so the line
always remains valid JSON.

## Severity levels

| Level   | Meaning                                  |
| ------- | ---------------------------------------- |
| `INFO`  | Normal operation and progress            |
| `WARN`  | Non-fatal anomaly, may be ignored        |
| `ERROR` | Failure requiring attention              |

## File permissions

| Path                                    | Mode | Owner    |
| --------------------------------------- | ---- | -------- |
| `/var/log/faigrid/`                     | 750  | root:adm |
| `/var/log/faigrid/grid-system.log`      | 640  | root:adm |
| `/var/log/faigrid/grid-events.jsonl`    | 640  | root:adm |

The `adm` group membership required by these `root:adm` permissions is
established at install time by `core/heart/scripts/install.sh`, which adds
the `grid` service user to the `adm` group (guarded: only when both the
`grid` user and the `adm` group exist).

## Overriding the log directory

`LOG_DIR` is overridable via the environment. `log_event` resolves its
target directory as `"${LOG_DIR:-/var/log/faigrid}"`, so a non-root caller
(or a test/container) can redirect writes to a writable path without root:

```bash
export LOG_DIR="/tmp/faigrid-test"
log_event "system" "INFO" "hello"
```

Both `grid-system.log` and `grid-events.jsonl` are written relative to the
resolved `LOG_DIR`. This is used by the unit test suite
(`tests/unit/05-log-event.bats`) to exercise the write path as an
unprivileged caller.
