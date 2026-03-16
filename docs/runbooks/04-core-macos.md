# Step 02 — macOS client setup (SSH + VNC tunnels)

Goal:
- Quick SSH aliases
- VNC access via SSH tunnel (no open VNC ports on firewall)

## 1) SSH config
Copy from:
- `docs/templates/ssh-config.example`

Paste into:
- `~/.ssh/config`

Test:
- `ssh nexus-core`
- `ssh nexus-core-ops`

## 2) VNC tunnel scripts (recommended)
We keep VNC bound to localhost on the server and tunnel it from macOS.

Install scripts:
- `core/base/client/macos/nexus-vnc-ops.example`
- `core/base/client/macos/nexus-vnc-ops-stop.example`

Copy to:
- `~/bin/nexus-vnc-ops`
- `~/bin/nexus-vnc-ops-stop`

Make executable:
- `chmod +x ~/bin/nexus-vnc-ops ~/bin/nexus-vnc-ops-stop`

Add to PATH:
- `echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc`
- `source ~/.zshrc`

Run:
- `nexus-vnc-ops`
Stop:
- `nexus-vnc-ops-stop`

Connect VNC client to:
- `127.0.0.1:5901` (ops)
- `127.0.0.1:5902` (nexus)

## Notes on encryption warnings
Some VNC clients show warnings if TLS is not negotiated.
For LAN-only access, we prefer the security model:
- VNC bound to localhost on server
- SSH tunnel provides encryption end-to-end
