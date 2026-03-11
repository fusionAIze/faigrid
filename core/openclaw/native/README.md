# OpenClaw (native) — nexus-core module

Goal: run OpenClaw **natively on the host** (not inside Docker), while n8n+pg+redis run via Docker Compose.

Design principles:
- bind OpenClaw to **localhost** on nexus-core
- expose only through **nexus-edge** (reverse proxy + SSO/2FA)
- systemd-managed, hardened service
- data + config separated from code

Entry points:
- `server/control-center.sh` for service lifecycle on `nexus-core`
- `scripts/push-prod.sh` and `scripts/push-prod-config-only.sh` for repo-side config sync
- `docs/runbooks/step-02_5-openclaw-native.md`
- `docs/reference/openclaw-native.md`

## Golden Config + Env (no secrets in git)
- Server-side env (real secrets): /etc/openclaw/openclaw.providers.env
- Repo templates:
  - core/openclaw/env/openclaw.providers.env.example
  - core/openclaw/env/openclaw.channels.env.example
- Server gateway env template:
  - core/openclaw/native/server/openclaw.env.example
- Golden snapshot (sanitized):
  - docs/reference/openclaw.golden.json
