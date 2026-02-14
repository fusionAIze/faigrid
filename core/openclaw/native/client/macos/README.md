# macOS client helpers (OpenClaw UI)

These scripts are **examples**. Copy them to `~/bin/` on your Mac.

## Install

```bash
mkdir -p ~/bin
cp core/openclaw/native/client/macos/nexus-openclaw-ui.example ~/bin/nexus-openclaw-ui
cp core/openclaw/native/client/macos/nexus-openclaw-ui-stop.example ~/bin/nexus-openclaw-ui-stop
chmod +x ~/bin/nexus-openclaw-ui ~/bin/nexus-openclaw-ui-stop
```

Ensure your `PATH` contains `~/bin`.

## SSH host alias

Your `~/.ssh/config` should contain a host entry like:

```sshconfig
Host nexus-core-ops
  HostName <core-ip-or-dns>
  User <ssh-user>
```

## Token retrieval (recommended)

To avoid typing a sudo password on every run, allow exactly one command via sudoers on core:

- `/bin/cat /etc/openclaw/secret/gateway.token`

See: `docs/templates/sudoers/openclaw-token-read.example`

