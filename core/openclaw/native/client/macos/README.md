# OpenClaw UI (macOS helper)

## Install
```bash
cp core/openclaw/native/client/macos/grid-openclaw-ui.example ~/bin/grid-openclaw-ui
cp core/openclaw/native/client/macos/grid-openclaw-ui-stop.example ~/bin/grid-openclaw-ui-stop
chmod +x ~/bin/grid-openclaw-ui ~/bin/grid-openclaw-ui-stop
```

## Run
```bash
grid-openclaw-ui
```

## Stop
```bash
grid-openclaw-ui-stop
```

## Requirements
- SSH host alias exists on the Mac (e.g. `grid-core-ops`)
- On core: `/etc/openclaw/secret/gateway.token` readable either directly or via sudo allowlist
- OpenClaw gateway bound to loopback on core port `18789`
