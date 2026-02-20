# macOS client helpers

- `nexus-openclaw-ui.example` — opens OpenClaw UI via SSH tunnel and copies token to clipboard.
- `nexus-openclaw-ui-stop.example` — stops tunnels (default port range 19089..19108).

Install locally:

```bash
cp nexus-openclaw-ui.example ~/bin/nexus-openclaw-ui
cp nexus-openclaw-ui-stop.example ~/bin/nexus-openclaw-ui-stop
chmod +x ~/bin/nexus-openclaw-ui ~/bin/nexus-openclaw-ui-stop
```

Run:

```bash
nexus-openclaw-ui
```
