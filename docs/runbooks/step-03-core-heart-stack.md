# Step 03 — Core Heart Stack (n8n + Postgres + Redis + OpenClaw placeholder)

Goal: Bring `nexus-core` into productive state with secure-by-default local services.
Only SSH (LAN) is open. n8n binds to localhost and will later be exposed via the edge gate (SSO/2FA).

## 0) Preconditions
- Step 02 (base) done: users, SSH hardening, VNC optional
- `nexus` can SSH into `nexus-core`
- Repo cloned on `nexus-core`:
  - `git clone https://github.com/<you>/fusionaize-nexus-labs.git`

## 1) Copy stack to /opt
On `nexus-core` as user `nexus`:
- `cd ~/fusionaize-nexus-labs`
- `bash core/heart/scripts/install.sh`

Then:
- edit `/opt/fusionaize-nexus/core-heart/.env`
  - set `N8N_ENCRYPTION_KEY`, `POSTGRES_PASSWORD`, `WEBHOOK_SHARED_SECRET`

Restart stack:
- `cd /opt/fusionaize-nexus/core-heart/compose`
- `docker compose --env-file /opt/fusionaize-nexus/core-heart/.env up -d`

## 2) Verify
- `docker ps`
- `curl -I http://127.0.0.1:5678`

## 3) Security posture (default)
- n8n bound to `127.0.0.1:5678` only
- DB/Redis only on internal docker network
- no external exposure on core

## 4) Next steps (Step 04)
- Put `nexus-edge` in front:
  - reverse proxy to core n8n
  - add SSO/2FA (Authentik/Authelia)
  - add CrowdSec
- Enable queue mode (Redis) + runner pattern
- Define OpenClaw deployment and connect it (webhooks/agents)

