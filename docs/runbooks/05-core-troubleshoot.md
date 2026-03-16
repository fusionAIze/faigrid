# Step 02 — Troubleshooting

## VNC shows "unencrypted" warning
Expected if VNC auth is not using TLS.
If you use SSH tunneling (recommended), the transport is encrypted by SSH.

Server should bind to localhost:
- `ss -tulpn | egrep ':5901|:5902'`
should show `127.0.0.1` / `::1` only.

## systemctl --user fails with DBUS/XDG_RUNTIME_DIR not set
When enabling user services via sudo, set XDG_RUNTIME_DIR:
- `sudo -u <user> XDG_RUNTIME_DIR=/run/user/$(id -u <user>) systemctl --user ...`

Also enable linger:
- `sudo loginctl enable-linger <user>`

## VNC session missing dbus / settings errors
Ensure dbus-x11 is installed:
- `sudo apt-get install -y dbus-x11`

Prefer default TigerVNC session script:
- `/etc/X11/Xtigervnc-session` (already used by vncserver)

## Port already in use (local tunnel)
Kill old tunnel:
- `pkill -f "ssh.*-L 5901:localhost:5901"`
or use your stop script.

## SSH key problems (Permission denied publickey)
Confirm:
- correct IdentityFile in ~/.ssh/config
- `ssh -i <key> user@host`
- key added to agent (`ssh-add -K <key>` on macOS, if desired)
