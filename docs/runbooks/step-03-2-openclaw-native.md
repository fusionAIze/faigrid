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
