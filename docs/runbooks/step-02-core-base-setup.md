# Step 02 — Core (Base setup)

Target: `nexus-core` (Debian stable, LAN node).

This step covers:
- hostname + static IP (recommended via router reservation)
- SSH hardening (key-only)
- `nexus` + `nexus-ops` users
- TigerVNC (localhost-only) + XFCE
- firewall baseline (UFW: SSH only)
- verification

## 0) Assumptions
- LAN: `192.168.178.0/24`
- Core: `nexus-core` at `192.168.178.20` (example)
- Users:
  - `nexus` (admin/bootstrap, sudo)
  - `nexus-ops` (daily operator, sudo, NOT docker)

## 1) Hostname + IP
Set hostname on Debian:
- `sudo hostnamectl set-hostname nexus-core`

Prefer router DHCP reservation for stable IP.
If you must configure a static IP on Debian, document the chosen method (NetworkManager/systemd-networkd).

## 2) Create users
If not already created:
- `sudo adduser nexus`
- `sudo usermod -aG sudo nexus`

Daily ops user:
- `sudo adduser nexus-ops`
- `sudo usermod -aG sudo nexus-ops`

Ensure `nexus-ops` is NOT in docker group:
- `sudo gpasswd -d nexus-ops docker 2>/dev/null || true`
- `id nexus-ops`

## 3) Sudo timeout (optional but recommended)
Create sudoers drop-in:
- `sudo visudo -f /etc/sudoers.d/10-nexus-timeout`

Use template:
- `docs/templates/sudoers-timeout.example`

Validate:
- `sudo visudo -c`

## 4) SSH hardening (key-only)
Copy the repo to the core (or clone it):
- `git clone <your-fork-url>`
- `cd fusionaize-nexus-labs/core/base`

Apply hardening:
- `./scripts/ssh-hardening-apply.sh`

Confirm effective settings:
- `sudo sshd -T | egrep -i 'permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|allowusers'`

## 5) Install TigerVNC + XFCE
Install packages:
- `./scripts/vnc-install.sh`

## 6) Configure VNC per user (localhost only)
For each user, pick a display:
- `nexus-ops` -> `:1` (port 5901)
- `nexus` -> `:2` (port 5902)

Setup per user:
- `./scripts/vnc-user-setup.sh nexus-ops 1`
- `./scripts/vnc-user-setup.sh nexus 2`

Set VNC passwords (manual):
- `sudo -u nexus-ops vncpasswd`
- `sudo -u nexus vncpasswd`

Enable services (manual; works even without active GUI login):
- `sudo -u nexus-ops XDG_RUNTIME_DIR=/run/user/$(id -u nexus-ops) systemctl --user daemon-reload`
- `sudo -u nexus-ops XDG_RUNTIME_DIR=/run/user/$(id -u nexus-ops) systemctl --user enable --now vncserver@1.service`

- `sudo -u nexus XDG_RUNTIME_DIR=/run/user/$(id -u nexus) systemctl --user daemon-reload`
- `sudo -u nexus XDG_RUNTIME_DIR=/run/user/$(id -u nexus) systemctl --user enable --now vncserver@2.service`

Verify listening sockets are localhost only:
- `sudo ss -tulpn | egrep ':5901|:5902'`

## 7) Firewall (UFW)
Baseline: SSH from LAN only.
VNC is accessed via SSH tunnel -> keep VNC ports closed.

Apply:
- `./scripts/ufw-apply.sh`

Verify:
- `sudo ufw status verbose`

## 8) Verify
Run:
- `./scripts/verify.sh`

