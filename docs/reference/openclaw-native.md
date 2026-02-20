# OpenClaw Native (core gateway)

## Overview
Runs OpenClaw gateway as a `systemd` service on the core node, bound to loopback, and exposed to clients via SSH tunnel.
Auth is token-based.

Core paths:
- Token secret: `/etc/openclaw/secret/gateway.token` (0640, root:openclaw)
- Env: `/etc/openclaw/openclaw.env` (0640, root:openclaw)
- Token env: `/etc/openclaw/openclaw.token.env` (0640, root:openclaw)
- State: `/var/lib/openclaw/.openclaw`

Port:
- Gateway: `18789/tcp` (loopback only)

## Server (core Linux) — install
```bash
cd core/openclaw/native/server
sudo ./install.sh --version 2026.2.19-2
```

Rotate token:
```bash
sudo ./install.sh --rotate-token
sudo systemctl restart openclaw.service
```

## Server — update
```bash
cd core/openclaw/native/server
sudo ./update.sh --version 2026.2.19-2
```

## Server — verify
```bash
cd core/openclaw/native/server
sudo ./verify.sh
```

## Server — control center
```bash
cd core/openclaw/native/server
sudo ./control-center.sh status
sudo ./control-center.sh logs
sudo ./control-center.sh restart
```

## Server — uninstall
Keep token, wipe state:
```bash
cd core/openclaw/native/server
sudo ./uninstall.sh --wipe-state --keep-token
```

Remove token too:
```bash
sudo ./uninstall.sh --wipe-state
```

## Client (macOS) — UI helper via SSH tunnel
Install:
```bash
cp core/openclaw/native/client/macos/nexus-openclaw-ui.example ~/bin/nexus-openclaw-ui
cp core/openclaw/native/client/macos/nexus-openclaw-ui-stop.example ~/bin/nexus-openclaw-ui-stop
chmod +x ~/bin/nexus-openclaw-ui ~/bin/nexus-openclaw-ui-stop
```

Run:
```bash
nexus-openclaw-ui
```

Stop tunnels:
```bash
nexus-openclaw-ui-stop
```
