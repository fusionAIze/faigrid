# OpenClaw (native on core)

Goal: run OpenClaw **natively** on `nexus-core` (Debian) as a system service, while the "core heart"
(n8n + postgres + redis) runs in Docker.

This folder is a **repo skeleton**:
- scripts are templates to run on the Debian host
- configs are examples (systemd unit placeholder)
- env examples contain no secrets

## Install (on Debian host)
Reference from docs:
- `curl -fsSL https://openclaw.ai/install.sh | bash`
- `openclaw onboard --install-daemon`
- `openclaw gateway status`
- `openclaw dashboard`

## Security posture
- keep OpenClaw internal (localhost / LAN) and expose only via edge reverse proxy if needed.
