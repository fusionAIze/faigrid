# Step 09 — grid-external (Public Cloud) Deployment

This runbook describes how to set up the **grid-external** role on a public VPS (e.g., Hetzner, DigitalOcean) to host exposed instances of n8n and Plane.so.

## Goal State
- Exposed n8n (https://n8n.your-agency.com)
- Exposed Plane PM (https://plane.your-agency.com)
- Auto-TLS via Caddy (Let's Encrypt)
- Secure-by-default (isolated Docker networks)

## 1) Prepare the Cloud Server
- Provision a minimal Ubuntu/Debian VPS.
- Add your SSH key for the `nexus` user (or your primary user).
- Install Docker and Docker Compose.

## 2) Deploy via Nexus Orchestrator
From your local machine:

```bash
./install.sh --mode remote --target root@your-cloud-ip --role external --action install
```

### 2.1 Strategic Installation
You can install specific components if the server is already running other apps:

```bash
# Only install n8n
./install.sh --mode remote --target root@your-cloud-ip --role external --action install --component n8n
```

## 3) Domain & SSL Configuration
1. Point your A-records (`n8n.your-domain.com`, `plane.your-domain.com`) to the VPS IP.
2. Edit `external/config/Caddyfile` on the host (or update via repo).
3. Restart Caddy:

```bash
./install.sh --mode remote --target root@your-cloud-ip --role external --action control --action restart --component caddy
```

## 4) Connectivity: Cloud-to-Core
Secure your cloud-to-core communication by using the **Internal HTTPS** scripts or a secure tunnel (Tailscale) as described in `07-tunneling.md`.

## 5) Verification
Run the diagnostics:
```bash
./install.sh --mode remote --target root@your-cloud-ip --role external --action verify
```
