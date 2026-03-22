# Step 02.5 — OpenClaw (native on grid-core)

## Target outcome
- OpenClaw runs as a **native systemd service** on `grid-core`
- bound to `127.0.0.1:18789`
- later exposed via `grid-edge` (reverse proxy + SSO/2FA)

## Repo locations
- Module: `core/openclaw/native/`
- Reference doc: `docs/reference/openclaw-native.md`
- Example env: `core/openclaw/native/server/openclaw.env.example`
- Example systemd: `core/openclaw/native/server/openclaw.service`
- Control-center: `core/openclaw/native/server/control-center.sh`

## Host-side planned paths (grid-core)
- CLI: `/usr/local/bin/openclaw`
- Env dir: `/etc/openclaw/openclaw.env`  (not in git)
- Token env: `/etc/openclaw/openclaw.token.env`  (not in git)
- Token secret: `/etc/openclaw/secret/gateway.token`
- State dir: `/var/lib/openclaw/.openclaw`

## Install plan (to execute later on grid-core)
1) Ensure Node 22+ + npm present
2) Create service user `openclaw`
3) Install `openclaw@<version>` globally via npm
4) Generate `/etc/openclaw/openclaw.env` + token files
5) Install systemd unit and enable it
6) Verify service status and loopback listener

## Execution
- Install:
  - `cd core/openclaw/native/server`
  - `sudo ./install.sh --version 2026.2.19-2`
- Verify:
  - `sudo ./verify.sh`
- Operate:
  - `sudo ./control-center.sh status`
  - `sudo ./control-center.sh logs`
