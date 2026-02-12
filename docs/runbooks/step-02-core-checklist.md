# Step 02 — Core Checklist (up to VNC + SSH)

Use this as a "done list" + expected outputs.

## A) Identity
- [ ] Hostname is `nexus-core`
  - `hostname`

- [ ] Core has expected IPv4 (example: `192.168.178.20`)
  - `ip -4 addr show`

## B) Users
- [ ] `nexus` exists and is in sudo
  - `id nexus` (groups include `sudo`)

- [ ] `nexus-ops` exists and is in sudo
  - `id nexus-ops` (groups include `sudo`)

- [ ] `nexus-ops` NOT in docker
  - `id nexus-ops` (no `docker` group)
  - optional: `sudo gpasswd -d nexus-ops docker`

## C) SSH hardening effective
Expected (example):
- `permitrootlogin no`
- `passwordauthentication no`
- `kbdinteractiveauthentication no`
- `pubkeyauthentication yes`
- `allowusers nexus nexus-ops`
- `maxauthtries 3`
- `logingracetime 20`

Command:
- `sudo sshd -T | egrep -i 'permitrootlogin|passwordauthentication|kbdinteractiveauthentication|challengeresponseauthentication|pubkeyauthentication|allowusers|maxauthtries|logingracetime'`

## D) Firewall baseline
- [ ] UFW installed and active
- [ ] Incoming default deny, outgoing allow
- [ ] Port 22 allowed only from LAN CIDR

Command:
- `sudo ufw status verbose`

Expected:
- `22/tcp ALLOW IN 192.168.178.0/24`

## E) VNC installed
- [ ] Packages installed: TigerVNC + XFCE + dbus-x11
  - `dpkg -l | egrep 'tigervnc|xfce4|dbus-x11' | head`

## F) VNC configured (localhost only)
Recommended:
- `nexus-ops` display :1 -> port 5901
- `nexus` display :2 -> port 5902

Check:
- `sudo ss -tulpn | egrep ':5901|:5902'`

Expected:
- listening on `127.0.0.1` and/or `::1` only (NOT 0.0.0.0)

## G) systemd user units running
For each user:
- `sudo -u <user> XDG_RUNTIME_DIR=/run/user/$(id -u <user>) systemctl --user status vncserver@<display>.service --no-pager`

Expected:
- `Active: active (running)`

## H) Client (macOS) SSH aliases
- [ ] `~/.ssh/config` contains at least: `nexus-edge`, `nexus-core`, `nexus-core-ops`
- [ ] SSH works:
  - `ssh nexus-core`
  - `ssh nexus-core-ops`

## I) Client (macOS) VNC tunnel
- [ ] tunnel script runs and opens VNC viewer (or at least keeps tunnel up)
- [ ] connect to: `127.0.0.1:5901` (ops) or `127.0.0.1:5902` (nexus)

