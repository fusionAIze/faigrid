# 17 - The grid-worker serves, and keeps serving

**Scope.** This runbook covers the durability of the inference endpoint on the
grid-worker `azrielenoch@192.168.178.30:8080`. It records the operator action
that makes the server outlive the SSH session that used to hold it, and the
checks that prove, from a different host, that it does. It changes nothing on
the worker itself; the worker-side steps below are performed by the operator.

**Lane.** GO-008 (`tests/integration/09-worker-reachability.bats`). The lane
creates this runbook and that test; it owns no worker-side code.

---

## 1. Measurements this runbook is built on

| Fact | Value | Measured |
| --- | --- | --- |
| Worker address reached on the LAN | `192.168.178.30` (interface `en5`) | 2026-09-25 |
| Same host's `en0` address | `192.168.178.116` (Wi-Fi) | 2026-09-25 |
| Server bind | `0.0.0.0:8080`, OpenAI-compatible `/v1` | 2026-09-25 |
| Engine | `/opt/homebrew/bin/llama-server` (Homebrew) | 2026-09-24 |
| Engine argv | `-c 8192 --parallel 1 -fa on -ctk q8_0 -ctv q8_0 -ngl 99 --host 0.0.0.0 --port 8080` | 2026-09-25 |
| api-key | required; no key -> 401, wrong key -> 401, correct key -> 200 | 2026-09-25 |
| Key source | envctl cluster `faigrid`, variable `LLAMA_API_KEY`, on the worker at `~/.config/envctl/faigrid.env` (mode 600) | 2026-09-24 |
| Wake source | USB Ethernet `en5`, MAC `00:e0:4f:82:c0:bc`, `womp 1` | 2026-09-25 |
| WOL / sleep | WOL active; the machine sleeps (clamshell / idle) | 2026-09-25 |
| Server durability | **none**: the server was the foreground child of an `sshd-session` and died with it | 2026-09-25 |

Two corrections to the task text, measured rather than assumed:

* **D7's api-key amendment holds.** The GO-008 preconditions in the sequence say
  "no api-key", quoting an earlier D7. D7 was amended the same day
  (`prd.json`, D7 amendment) and the endpoint now answers `401 Invalid API Key`
  without `Authorization: Bearer <key>`. The key is passed to `llama-server` as
  an **environment variable**, never as `--api-key`, because argv is readable by
  any local user through `ps` on macOS.
* **D6's forced command is not in effect.** As measured 2026-09-25, a plain
  `ssh azrielenoch@192.168.178.30 'echo ok'` lands in a normal shell; the key
  is a plain key without a `command=` prefix. D6 exists so that a restart is a
  reconnection; this runbook replaces that with launchd supervision, so the
  endpoint no longer depends on a live session at all.

---

## 2. The problem

The server was started as the foreground process of an SSH session:

```
llama-server        ppid  sshd-session: azrielenoch@notty   (measured 2026-09-25)
```

Every consumer that reached `http://192.168.178.30:8080/v1` depended on that one
session staying open. When it closed, the server died. That is what criterion 1
of GO-008 names, and it is what this runbook fixes.

The fix is a **user LaunchAgent**: launchd starts `/Users/azrielenoch/start_api.sh`
at load and restarts it if it exits (`KeepAlive`). A user agent needs no
administrative rights - unlike a system LaunchDaemon - which matters because the
worker account is a fixed appliance (D6).

`~/start_api.sh` already does the right things and is **not modified**:

* it reads `LLAMA_API_KEY` from `~/.config/envctl/faigrid.env` and fails closed
  when it is absent;
* it uses absolute paths (`/opt/homebrew/bin/llama-server`), because launchd, like
  an sshd forced command, loads no shell profile (the absolute-path trap);
* it wraps the server in `caffeinate -dimsu`, so the machine is held awake for as
  long as the server runs.

---

## 3. Operator action - install the LaunchAgent

Run the following as `azrielenoch` on the worker (`192.168.178.30`). The exact
file is `~/Library/LaunchAgents/com.fusionaize.grid-worker.plist`.

```sh
mkdir -p ~/Library/LaunchAgents ~/Library/Logs

cat > ~/Library/LaunchAgents/com.fusionaize.grid-worker.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.fusionaize.grid-worker</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/azrielenoch/start_api.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>StandardOutPath</key>
  <string>/Users/azrielenoch/Library/Logs/grid-worker.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/azrielenoch/Library/Logs/grid-worker.err.log</string>
</dict>
</plist>
PLIST

# Stop any session-bound server and hand the endpoint to launchd.
launchctl bootout gui/$(id -u)/com.fusionaize.grid-worker 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.fusionaize.grid-worker.plist
launchctl kickstart -k gui/$(id -u)/com.fusionaize.grid-worker
```

The existing session-bound server (if any) must be stopped before bootstrap, or
`llama-server` cannot bind the port and launchd will retry every 10 s. Stopping
it is done by closing the SSH session that holds it - that is criterion 1's
"disconnect entirely".

### Verify on the worker

```sh
launchctl print gui/$(id -u)/com.fusionaize.grid-worker | grep -E 'state|keepalive'
ps -Ao pid=,ppid=,command= | egrep 'llama-server|caffeinate'
```

The serving process's parent chain must terminate at `launchd` (pid 1) and must
contain **no** `sshd`. Before the fix the first ancestor was
`sshd-session: azrielenoch@notty`; after it, it is launchd.

### Remove the LaunchAgent (rollback)

```sh
launchctl bootout gui/$(id -u)/com.fusionaize.grid-worker 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.fusionaize.grid-worker.plist
```

---

## 4. Verify from another host

Run these from the workstation. They are the external proof the lane's test also
encodes. The api-key is read on the workstation and is never printed.

```sh
KEY="$(envctl get faigrid LLAMA_API_KEY)"

# C1: the model list answers from this host, with no SSH session holding it.
curl -fsS -H "Authorization: Bearer ${KEY}" http://192.168.178.30:8080/v1/models

# C1: show the disconnect. Close every SSH client to the worker, then re-probe:
ps -Ao pid=,command= | awk '$2=="ssh"' | grep '192.168.178.30'
#   -> no line naming start_api.sh means nothing on this host holds the server
curl -fsS -H "Authorization: Bearer ${KEY}" http://192.168.178.30:8080/v1/models

# C2: caffeinate holds the machine awake while the server runs.
ssh azrielenoch@192.168.178.30 "pmset -g | grep -i 'sleep prevented by caffeinate'"

# C2: force a sleep, wake by WOL, and probe again without touching the worker.
ssh azrielenoch@192.168.178.30 'pmset sleepnow'
python3 - <<'PY'
import socket
mac = "00:e0:4f:82:c0:bc"
data = bytes.fromhex("ff" * 6 + mac.replace(":", "") * 16)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
s.sendto(data, ("192.168.178.255", 9))
PY
# poll until it answers; record the elapsed time as the wake time
```

### C3 - an unreachable worker is named by endpoint

`worker/lib/worker-env.sh` (GO-013) probes the HTTP endpoint, not a CLI, and
names the URL on failure. Source it and point it at the worker:

```sh
source worker/lib/worker-env.sh
WORKER_HEALTH_URL="http://192.168.178.30:8080/v1/models" worker_health_check
```

When the endpoint does not answer the output names it, rather than reporting a
bare connection error:

```
[grid-worker] ERROR: inference endpoint did NOT answer: http://192.168.178.30:8080/v1/models
```

A generic `curl: (7) Failed to connect` alone is not sufficient evidence for
criterion 3; the endpoint must appear by name.

---

## 5. What this runbook deliberately does not do

* **No tunnel, no sidecar, no reverse tunnel.** D7 binds the LAN directly; D1's
  tunnel is withdrawn. Nothing here reintroduces it.
* **No change to `~/start_api.sh` or `~/.ssh`.** The start script is reused
  unchanged; the SSH authorization is not this lane's to alter.
* **No system LaunchDaemon.** A user LaunchAgent needs no admin rights; a
  LaunchDaemon would, and the worker account is not an administrator.
* **No secret in this repository.** The key is referenced by cluster and
  variable name only (`faigrid` / `LLAMA_API_KEY`); its value is never written.

## 6. The check

`tests/integration/09-worker-reachability.bats` runs this from the workstation:

* **C1** the endpoint answers from this host and the serving process is not bound
  to an SSH session (no `sshd` ancestor; or, when the worker's SSH is not
  reachable for inspection, no SSH session on this host holds the endpoint);
* **C2** `caffeinate` holds the machine awake and the endpoint is supervised by a
  `KeepAlive` launchd job rather than a live session;
* **C3** an unreachable endpoint is named by URL, not by a generic failure.

Run it with the repository's own bats:

```sh
bash tests/run_tests.sh --integration
```
