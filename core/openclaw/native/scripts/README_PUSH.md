# OpenClaw Prod Push Scripts (safe-by-default)

These scripts are DRY-RUN by default.
They only apply changes when you pass `--apply`.

## Preflight (important)
Both scripts require `sudo -n` on the server to avoid hanging.
If `sudo -n` is not available, run once:

  ssh -tt nexus-core 'sudo -v'

Then re-run the script.

## Scripts

### 1) Config-only
Dry-run (diff only):
  HOST_ALIAS=nexus-core core/openclaw/native/scripts/push-prod-config-only.sh

Apply + restart:
  HOST_ALIAS=nexus-core core/openclaw/native/scripts/push-prod-config-only.sh --apply --restart

### 2) Config + Env (secrets)
This expects a LOCAL gitignored file:
  core/openclaw/env/openclaw.providers.env

Dry-run:
  HOST_ALIAS=nexus-core core/openclaw/native/scripts/push-prod.sh

Apply + restart:
  HOST_ALIAS=nexus-core core/openclaw/native/scripts/push-prod.sh --apply --restart

## Safety
- openclaw.json diff is sanitized (no tokens/keys shown).
- providers.env diff only shows KEY=SET/EMPTY (never values).
