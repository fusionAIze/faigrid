# OpenClaw UI (macOS helper)

## Install
```bash
cp core/openclaw/native/client/macos/nexus-openclaw-ui.example ~/bin/nexus-openclaw-ui
cp core/openclaw/native/client/macos/nexus-openclaw-ui-stop.example ~/bin/nexus-openclaw-ui-stop
chmod +x ~/bin/nexus-openclaw-ui ~/bin/nexus-openclaw-ui-stop
```

## Run
```bash
nexus-openclaw-ui
```

## Stop
```bash
nexus-openclaw-ui-stop
```

## Requirements
- SSH host alias exists on the Mac (e.g. `grid-core-ops`)
- On core: `/etc/openclaw/secret/gateway.token` readable either directly or via sudo allowlist
- OpenClaw gateway bound to loopback on core port `18789`
