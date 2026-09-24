# Worker setup: generic vs machine-specific (reference)

**Measured basis: 2026-09-24, the grid-worker of the veeona go-live round.**
This page separates the parts of that setup that are a property of *any*
grid-worker from the parts that belong to *that one MacBook*. The distinction is
not bookkeeping: a surface that names one machine cannot be reused, and the two
absolute-path incidents in this round (a non-interactive `PATH` on nexus-core and
again on the worker) are the measurement that says the reusable part belongs in
code, not in a runbook.

The generic code lives in [`worker/lib/worker-env.sh`](../../worker/lib/worker-env.sh)
and is exercised by `tests/unit/11-worker-env.bats`. Every host-specific input
arrives as a `WORKER_*` environment variable, so the file itself names no host.

## Classification

| Element | Class | What makes it so |
|---|---|---|
| llama.cpp engine | **generic** | The engine name and the server flags are the same on every worker; GO-010 already made it first-class in `worker/scripts/install.sh`. Which model it loads is a separate, machine-specific input. Generic code: `worker_llama_server_bin` / `worker_resolve_bin`. |
| api-key source (mechanism) | **generic** | Reading a key from a `key=value` env file and refusing to start without one is portable. Generic code: `worker_read_api_key`, which fails closed on a missing file, an unreadable file, an absent variable or an empty value, and never prints the key. |
| api-key source (path and ACL) | **machine-specific** | The path and who may read it belong to the host: on the measured worker the key is the `LLAMA_API_KEY` cluster entry in `~/.config/envctl/faigrid.env` (mode 600), and `envctl` is installed only under the operator account and ACL-blocked for the worker account, which is why the file is read directly. The path is therefore *configuration* (`WORKER_API_KEY_FILE`), never a literal in the generic code. |
| absolute-path requirement | **generic** | It is a property of non-interactive sessions, not of a machine: an sshd forced command, launchd and cron load no shell profile, so `~/.local/bin` (VT-001 on nexus-core) and `/opt/homebrew/bin` (the worker) fall off `PATH`. The same fix applies everywhere. Generic code: `worker_resolve_bin` resolves an absolute path from an explicit override, then `PATH`, then `WORKER_BIN_DIRS`. |
| caffeinate | **generic (macOS)** | Any MacBook worker that sleeps drops its endpoint; `caffeinate -dimsu` holding the machine awake for the server's lifetime is host-independent. `WORKER_CAFFEINATE=auto` enables it only on Darwin with the binary present, so the same code is inert on a Linux worker. Generic code: `worker_caffeinate_enabled` / `worker_caffeinate_prefix`. |
| service durability | **machine-specific** | The durable mechanism on this worker is imposed by decision D6: `authorized_keys` carries a forced command and the account has no administrative access, so reconnecting *is* restarting the server, and no portable installer can reproduce that. The generic building block that does generalise - knowing from a pidfile whether the server is still alive - is provided as `worker_service_running`. |
| health check | **generic** | A CLI presence check (`ollama list`, `lms status`) is not evidence that the HTTP endpoint answers; an HTTP probe is portable and is the check `worker/scripts/verify.sh` lacked. Generic code: `worker_health_check`, which names the endpoint and returns non-zero when it does not answer. |

## Host-specific inputs, kept out of the generic code

These are supplied by the operator's environment, not baked into `worker/`:

- `WORKER_API_KEY_FILE` - path to the env file holding the key (no default).
- `WORKER_API_KEY_VAR` - the variable to read (default `LLAMA_API_KEY`).
- `WORKER_MODEL_PATH` - the model file to load (no default).
- `WORKER_BIND_ADDR` / `WORKER_PORT` - the listen address and port.
- `WORKER_LLAMA_SERVER_BIN` / `WORKER_BIN_DIRS` - location overrides for a
  worker whose engine is not in a well-known directory.
- `WORKER_HEALTH_URL` - the endpoint to probe.
- `WORKER_PIDFILE`, `WORKER_CTX_SIZE`, `WORKER_PARALLEL`, `WORKER_NGL`,
  `WORKER_CAFFEINATE`, `WORKER_HEALTH_TIMEOUT` - runtime tuning.

## The api-key is passed as an environment variable, never as a flag

The key is read into `LLAMA_API_KEY` and exported. It is deliberately **not**
passed as `--api-key`: on macOS `argv` is world-readable through `ps`, so a flag
would expose the key to any local process. `worker_print_llama_command` builds
the argv without it, and a test asserts the flag is absent.

> Note on the decision text: decision D7 reads "no tunnel, no sidecar, no
> api-key", while the measured setup of this round (and GO-014) carries
> `LLAMA_API_KEY`. This page classifies the **measured** state - the key is read
> and the start path fails closed without it - and flags the discrepancy rather
> than silently choosing one reading.

## What is deliberately not here

No tunnel, no sidecar, no reverse tunnel, and no machine address, user name,
model file name or key value. `grep` across `worker/` for a host, an account, a
model file name or a key looks for exactly those and finds none; the grep is the
proof that the surface stayed generic.
