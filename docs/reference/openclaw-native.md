# OpenClaw Native (core gateway)

## Overview
Runs the OpenClaw gateway as a `systemd` service on the core node.

- Gateway binds to **loopback** (recommended) and is reached from clients via **SSH tunnel**.
- Auth is **token-based**.
- Token is stored on core at:
  - `/etc/openclaw/secret/gateway.token` (mode `0640`, owner `root:openclaw`)

## Server (Debian core) — install

```bash
cd core/openclaw/native/server
sudo ./install.sh --version 2026.2.19-2
```

### Rotate token (optional)

```bash
sudo ./install.sh --rotate-token
sudo systemctl restart openclaw.service
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

Copy helper scripts:

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

## Requirements
- SSH host alias exists on the client, e.g. `nexus-core-ops`
- On core: SSH user is in group `openclaw` **or** sudo allowlist exists for reading the token
- OpenClaw gateway is bound to loopback on port `18789`
