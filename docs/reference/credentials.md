# Credentials & Secrets (reference)

## Principles
- Keep secrets OUT of Git.
- Use `.env` files locally only (never commit).
- Prefer per-project/per-service credentials (least privilege).
- Rotate keys regularly.

## For Step 03 (core heart)
- n8n encryption key: `N8N_ENCRYPTION_KEY` (must be stable)
- Postgres password: `POSTGRES_PASSWORD`
- n8n basic auth (optional): `N8N_BASIC_AUTH_*` (only if used)
- Webhook signatures (recommended): `WEBHOOK_SHARED_SECRET` (HMAC)
- OpenClaw API keys/tokens (as needed)

## Storage
- `.env` on grid-core at: `/opt/faigrid/core-heart/.env`
- Backups should NOT include raw secrets unless you explicitly encrypt backups.
