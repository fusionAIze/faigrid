# Step 02.5 — OpenClaw (native on nexus-core)

## Target outcome
- OpenClaw runs as a **native systemd service** on `nexus-core`
- bound to `127.0.0.1:3000`
- later exposed via `nexus-edge` (reverse proxy + SSO/2FA)

## Repo locations
- Module: `core/openclaw/native/`
- Example env: `core/openclaw/native/configs/openclaw.env.example`
- Example systemd: `core/openclaw/native/systemd/openclaw.service.example`
- Control-center: `core/openclaw/native/scripts/control-center.sh`

## Host-side planned paths (nexus-core)
- Install dir: `/opt/openclaw`
- Env dir: `/etc/openclaw/openclaw.env`  (not in git)
- Data dir: `/var/lib/openclaw`
- Logs dir: `/var/log/openclaw`

## Install plan (to execute later on nexus-core)
1) Ensure Node 22+ + npm present
2) Create service user `openclaw`
3) Create dirs and permissions
4) Install OpenClaw (official installer / release)
5) Place `/etc/openclaw/openclaw.env` based on the example
6) Install systemd unit and enable

> NOTE: The exact ExecStart will be finalized once the install method is confirmed on the host.
