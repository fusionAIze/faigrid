# OpenClaw Cheat Sheet (Nexus Labs)

## Server Paths (prod)
- State dir:      /var/lib/openclaw/.openclaw-prod
- Config:         /var/lib/openclaw/.openclaw-prod/openclaw.json
- Providers env:  /etc/openclaw/openclaw.providers.env
- Workspace:      /var/lib/openclaw/.openclaw/workspace-prod
- Memory:         /var/lib/openclaw/.openclaw/workspace-prod/memory

## Health / Status
- Channels:
  ocprod channels status --probe | sed -n '1,140p'
- Models:
  ocprod models status --probe --probe-max-tokens 16 | sed -n '1,140p'
- Logs:
  sudo journalctl -u openclaw.service -n 200 --no-pager

## Doctor (env loaded)
sudo -u openclaw -H bash -lc 'set -a; . /etc/openclaw/openclaw.providers.env; set +a; openclaw --profile prod doctor --non-interactive'

## Memory
- Index:
  sudo -u openclaw -H bash -lc 'set -a; . /etc/openclaw/openclaw.providers.env; set +a; openclaw --profile prod memory index --force'
- Search:
  ocprod memory search "query" --max-results 10 --min-score 0.2

## Control UI (macOS tunnel)
- Helpers:
  core/openclaw/native/client/macos/nexus-openclaw-ui.example
  core/openclaw/native/client/macos/nexus-openclaw-ui-stop.example
- Default local UI port: 19089 -> forwards to 127.0.0.1:18789

## Watchdog
- systemd timer:
  systemctl status openclaw-watchdog.timer --no-pager
  systemctl list-timers | grep openclaw-watchdog

## Discord behavior
- Bot replies reliably when mentioned (@Bot / @Azriel).
- Plain "Hey Azriel" without mention may be ignored depending on mention gating.
