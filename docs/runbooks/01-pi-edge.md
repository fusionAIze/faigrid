# Step 01 — grid-edge (Headless) Fresh Setup (Reference: Raspberry Pi OS Lite)

This runbook sets up the **grid-edge** role as a small, hardened edge appliance.

Important: grid-edge is a **role**, not a device.
Raspberry Pi OS Lite (64-bit) is used here as a reference implementation, but the same steps apply to any minimal Debian-based host (Pi, mini PC, VM, VPS).

## Goal state

- SSH-only host (no GUI)
- Pi-hole (LAN DNS + web dashboard)
- UFW firewall (deny-by-default)
- Optional: Caddy (reverse proxy / TLS termination)
- Optional: CrowdSec (abuse protection)
- Prepared for later: SSO/2FA (Authelia/Authentik) in front of public apps

## Prerequisites

- A reserved IP via DHCP reservation (recommended)
- LAN access (Ethernet recommended)
- A Pi-hole Teleporter export (teleporter_*.tar.gz) if migrating settings

## 0) Network planning (recommended)

Record these values:

- EDGE_IP (reserved via router DHCP reservation)
- GATEWAY_IP (router, e.g. 192.168.178.1)
- LAN_CIDR (e.g. 192.168.178.0/24)
- DNS strategy:
  - Option A: Router uses Pi-hole as DNS for the whole LAN
  - Option B: Only selected clients use Pi-hole

## 1) Install OS (reference: Raspberry Pi OS Lite 64-bit)

Use Raspberry Pi Imager and enable:

- Hostname: grid-edge
- SSH: enabled (prefer SSH key auth)
- User + password
- Locale/timezone

Boot the device and SSH in:

    ssh <user>@<EDGE_IP>

Update packages:

    sudo apt-get update
    sudo apt-get upgrade -y
    sudo reboot

## 2) Baseline hardening (SSH)

Recommended SSH settings:

- PermitRootLogin no
- PasswordAuthentication no (only after you verified SSH keys work)

Edit and restart:

    sudo nano /etc/ssh/sshd_config
    sudo systemctl restart ssh

## 3) Firewall baseline (UFW)

Install UFW:

    sudo apt-get install -y ufw

Auto-detect LAN CIDR (best-effort):

    LAN_CIDR=$(ip -o -f inet addr show | awk '/scope global/ {print $4; exit}')
    echo "LAN_CIDR=$LAN_CIDR"

Apply rules:

    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    # SSH (LAN only)
    sudo ufw allow from "$LAN_CIDR" to any port 22 proto tcp

    # DNS (LAN only)
    sudo ufw allow from "$LAN_CIDR" to any port 53 proto udp
    sudo ufw allow from "$LAN_CIDR" to any port 53 proto tcp

    # Reserve for reverse proxy (optional)
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp

    sudo ufw --force enable
    sudo ufw status verbose

## 4) Install Pi-hole

Install:

    curl -sSL https://install.pi-hole.net | bash

After installation:

    pihole status

### 4.1 Restore configuration (Teleporter)

From a LAN browser:

- http://<EDGE_IP>/admin
- Settings → Teleporter → Import
- Upload teleporter_*.tar.gz

## 5) DNS activation strategies

### Option A (whole LAN via router)

Set the router DNS server to EDGE_IP so all clients use Pi-hole.

### Option B (selected clients)

Configure DNS only on selected devices.

## 6) Optional: Caddy (reverse proxy / TLS termination)

Install and enable:

    sudo apt-get install -y caddy
    sudo systemctl enable --now caddy

Edit /etc/caddy/Caddyfile (example):

    n8n.example.com {
      reverse_proxy http://<CORE_IP>:5678
    }

Reload:

    sudo caddy reload --config /etc/caddy/Caddyfile

## 7) Optional: CrowdSec (abuse protection)

Install:

    sudo apt-get install -y crowdsec
    sudo systemctl enable --now crowdsec

Enable SSH collection:

    sudo cscli collections install crowdsecurity/sshd
    sudo systemctl restart crowdsec

## 8) Validation checklist

    sudo ss -tulpn
    sudo ufw status verbose
    pihole status

Expected:
- 22/tcp open (LAN only)
- 53/tcp+udp open (LAN only)
- 80/443 open if Caddy enabled
- no unexpected services listening

## 9) Hardening (recommended)

### 9.1 Disable Avahi (mDNS) if you don't need *.local
On minimal edge appliances, disabling Avahi reduces attack surface:

    sudo systemctl disable --now avahi-daemon.service avahi-daemon.socket
    sudo systemctl mask avahi-daemon.service avahi-daemon.socket

### 9.2 Unattended upgrades (security-only)

Enable unattended upgrades:

    sudo apt-get update
    sudo apt-get install -y unattended-upgrades
    sudo dpkg-reconfigure -plow unattended-upgrades

Harden to **security-only** by disabling the default "Debian" origin:

    sudo cp /etc/apt/apt.conf.d/50unattended-upgrades /etc/apt/apt.conf.d/50unattended-upgrades.bak
    sudo sed -i 's/^\(\s*\)"origin=Debian,codename=\${distro_codename},label=Debian";/\1\/\/ "origin=Debian,codename=${distro_codename},label=Debian";/' /etc/apt/apt.conf.d/50unattended-upgrades

Verify:

    grep -n 'label=Debian";' /etc/apt/apt.conf.d/50unattended-upgrades
    grep -n 'Debian-Security' /etc/apt/apt.conf.d/50unattended-upgrades

### 9.3 Backup (tarball + Teleporter)

Create a local config backup:

    sudo mkdir -p /var/backups/grid-edge/pihole
    sudo tar -czf /var/backups/grid-edge/pihole/etc-pihole_$(date +%F).tar.gz /etc/pihole /etc/dnsmasq.d

Recommended additional export (easy restore):
- Pi-hole UI -> Settings -> Teleporter -> Export


### Using the repo helper scripts (optional)

If you cloned this repo on the edge host, you can apply the firewall baseline via:

    cd edge/pi/scripts
    ./ufw-apply.sh

Override LAN CIDRs if needed:

    IPV4_LAN_CIDR="192.168.178.0/24" IPV6_ULA_CIDR="fdaf:a57b:d3e6:0::/64" ./ufw-apply.sh


## 10) Maintenance (repo helper scripts)

After cloning the repo on the edge host:

    cd edge/pi/scripts
    ./update.sh

To also update Pi-hole subsystems:

    DO_PIHOLE_UPDATE=1 ./update.sh

Create backups:

    ./backup.sh

