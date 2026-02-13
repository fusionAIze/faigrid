# OpenClaw (native) — nexus-core module

Goal: run OpenClaw **natively on the host** (not inside Docker), while n8n+pg+redis run via Docker Compose.

Design principles:
- bind OpenClaw to **localhost** on nexus-core
- expose only through **nexus-edge** (reverse proxy + SSO/2FA)
- systemd-managed, hardened service
- data + config separated from code

Entry points:
- scripts/control-center.sh
- docs/runbooks/step-02_5-openclaw-native.md
