# Step 03 — Core Heart Stack (n8n + Postgres + Redis + OpenClaw placeholder)

Goal: Bring `grid-core` into productive state with secure-by-default local services.
Only SSH (LAN) is open. n8n binds to localhost and will later be exposed via the edge gate (SSO/2FA).

## 0) Preconditions
- Step 02 (base) done: users, SSH hardening, VNC optional
- `grid` can SSH into `grid-core`
- Repo cloned on `grid-core`:
  - `git clone https://github.com/<you>/faigrid.git`

## 1) Copy stack to /opt
On `grid-core` as user `grid`:
- `cd ~/faigrid`
- `bash core/heart/scripts/install.sh`

Then:
- edit `/opt/faigrid/core-heart/.env`
  - set `N8N_ENCRYPTION_KEY`, `POSTGRES_PASSWORD`, `WEBHOOK_SHARED_SECRET`

Restart stack:
- `cd /opt/faigrid/core-heart/compose`
- `docker compose --env-file /opt/faigrid/core-heart/.env up -d`

## 2) Verify
- `docker ps`
- `curl -I http://127.0.0.1:5678`

## 3) Security posture (default)
- n8n bound to `127.0.0.1:5678` only
- DB/Redis only on internal docker network
- no external exposure on core

## 4) Next steps (Step 04)
- Put `grid-edge` in front:
  - reverse proxy to core n8n
  - add SSO/2FA (Authentik/Authelia)
  - add CrowdSec
- Enable queue mode (Redis) + runner pattern
- Define OpenClaw deployment and connect it (webhooks/agents)

