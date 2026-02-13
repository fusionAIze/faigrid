#!/usr/bin/env bash
set -euo pipefail

# Run from repo root
if [[ ! -d ".git" ]]; then
  echo "ERROR: run from repo root (where .git exists)."
  exit 1
fi

echo "[scaffold] Step 03.2 OpenClaw native (skeleton only)"

# Docs
mkdir -p docs/runbooks
touch docs/runbooks/step-03-2-openclaw-native.md

# Module tree
mkdir -p \
  core/openclaw/env \
  core/openclaw/configs/systemd \
  core/openclaw/scripts

touch \
  core/openclaw/README.md \
  core/openclaw/env/.env.example \
  core/openclaw/configs/systemd/openclaw-gateway.service.example \
  core/openclaw/scripts/00-scaffold-note.sh \
  core/openclaw/scripts/10-install-openclaw.sh \
  core/openclaw/scripts/20-onboard-openclaw.sh \
  core/openclaw/scripts/30-verify-openclaw.sh \
  core/openclaw/scripts/99-update-openclaw.sh \
  core/openclaw/scripts/90-uninstall-openclaw.sh \
  core/openclaw/.gitignore

echo "[scaffold] Writing skeleton contents..."

cat > core/openclaw/.gitignore <<'EOF'
# OpenClaw local runtime (never commit)
.env
.env.local
state/
data/
logs/
EOF

cat > core/openclaw/env/.env.example <<'EOF'
# OpenClaw (native) - example env (do NOT commit real secrets)
# Paths are referenced by OpenClaw docs as optional env vars:
#   OPENCLAW_HOME, OPENCLAW_STATE_DIR, OPENCLAW_CONFIG_PATH

OPENCLAW_HOME=/opt/openclaw
OPENCLAW_STATE_DIR=/var/lib/openclaw
OPENCLAW_CONFIG_PATH=/etc/openclaw/config.yaml

# Example port (keep internal; reverse proxy via edge)
OPENCLAW_PORT=3000
EOF

cat > core/openclaw/configs/systemd/openclaw-gateway.service.example <<'EOF'
# Example systemd unit (TEMPLATE)
# NOTE: final ExecStart depends on what the installer provides on Debian
# (openclaw CLI + gateway daemon). Keep this as a placeholder until we
# implement on the actual host.

[Unit]
Description=OpenClaw Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=openclaw
Group=openclaw
EnvironmentFile=-/etc/openclaw/openclaw.env
WorkingDirectory=/var/lib/openclaw
ExecStart=/usr/local/bin/openclaw gateway start
Restart=on-failure
RestartSec=2

# Hardening (basic)
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/openclaw /etc/openclaw

[Install]
WantedBy=multi-user.target
EOF

cat > core/openclaw/scripts/00-scaffold-note.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "This is a repo skeleton for OpenClaw native deployment."
echo "Do not run on macOS. Run templates later on the Debian host (nexus-core)."
EOF
chmod +x core/openclaw/scripts/00-scaffold-note.sh

cat > core/openclaw/scripts/10-install-openclaw.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Run on Debian host (nexus-core).
# Source: OpenClaw docs show installer script:
#   curl -fsSL https://openclaw.ai/install.sh | bash
#
# This script is a TEMPLATE. It intentionally does not manage secrets.

echo "[openclaw] installing via installer script..."
curl -fsSL https://openclaw.ai/install.sh | bash

echo
echo "[openclaw] next: run onboarding wizard (daemon install):"
echo "  openclaw onboard --install-daemon"
EOF
chmod +x core/openclaw/scripts/10-install-openclaw.sh

cat > core/openclaw/scripts/20-onboard-openclaw.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Run on Debian host (nexus-core).
# Docs show:
#   openclaw onboard --install-daemon
# Then:
#   openclaw gateway status
#   openclaw dashboard

echo "[openclaw] onboarding (installs daemon/service if supported)..."
openclaw onboard --install-daemon

echo
echo "[openclaw] check status:"
echo "  openclaw gateway status"
echo
echo "[openclaw] open UI:"
echo "  openclaw dashboard"
EOF
chmod +x core/openclaw/scripts/20-onboard-openclaw.sh

cat > core/openclaw/scripts/30-verify-openclaw.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "[openclaw] status checks"
command -v openclaw >/dev/null && echo "OK: openclaw in PATH" || (echo "ERR: openclaw not found" && exit 1)

echo
echo "[openclaw] gateway status (if available)"
openclaw gateway status || true

echo
echo "[openclaw] doctor (if available)"
openclaw doctor || true
EOF
chmod +x core/openclaw/scripts/30-verify-openclaw.sh

cat > core/openclaw/scripts/99-update-openclaw.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Placeholder: OpenClaw docs mention maintenance/updating.
# We'll implement once we confirm update mechanism on Debian host.
echo "[openclaw] update placeholder - implement after first host install"
echo "Try: openclaw --help / openclaw update (if supported)"
EOF
chmod +x core/openclaw/scripts/99-update-openclaw.sh

cat > core/openclaw/scripts/90-uninstall-openclaw.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Placeholder: docs mention uninstall.
# We'll implement once we confirm how the installer deploys on Debian host.
echo "[openclaw] uninstall placeholder - implement after first host install"
EOF
chmod +x core/openclaw/scripts/90-uninstall-openclaw.sh

cat > core/openclaw/README.md <<'EOF'
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
EOF

cat > docs/runbooks/step-03-2-openclaw-native.md <<'EOF'
# Step 03.2 — OpenClaw (native on nexus-core)

This step only adds the **repo skeleton** (templates + runbook).
Actual installation happens later on the Debian host (`nexus-core`).

## Source (docs)
From the OpenClaw docs pages/screens:
- Install script (macOS/Linux): `curl -fsSL https://openclaw.ai/install.sh | bash`
- Onboarding / daemon: `openclaw onboard --install-daemon`
- Checks: `openclaw gateway status`
- UI: `openclaw dashboard`

## Repo locations
- Module: `core/openclaw/`
- Templates:
  - env example: `core/openclaw/env/.env.example`
  - systemd unit example: `core/openclaw/configs/systemd/openclaw-gateway.service.example`
  - scripts (templates): `core/openclaw/scripts/*.sh`

## Next (when executing on nexus-core)
1. Run: `core/openclaw/scripts/10-install-openclaw.sh`
2. Run: `core/openclaw/scripts/20-onboard-openclaw.sh`
3. Verify: `core/openclaw/scripts/30-verify-openclaw.sh`

We’ll finalize the real systemd unit + paths after the first successful install,
because the exact ExecStart/install layout is determined by the installer.
EOF

echo
echo "[scaffold] done."
echo "Next:"
echo "  git status"
echo "  git add docs/runbooks core/openclaw scripts/scaffold-step03-2-openclaw-native.sh"
echo "  git commit -m \"scaffold(step03.2): add OpenClaw native module skeleton\""

