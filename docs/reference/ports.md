# Ports (reference)

This document is a **generic reference** for the FusionAIze Nexus Labs architecture.

**Rules**
- Do **not** put real public domains, IPs, or secret endpoints here.
- Services on `nexus-core` should be **localhost-only** or **docker-internal** by default.
- Expose public services **only via `nexus-edge`** (reverse proxy + SSO/2FA).
- If you want “obscure” ports, do it on the **client-side tunnel ports**, not on the infrastructure.

---

## Default ports (logical / upstream defaults)

### nexus-edge (example)
- 22/tcp      SSH (LAN only)
- 53/tcp+udp  DNS (LAN only; Pi-hole if used)
- 80/tcp      HTTP (optional; ACME / redirect to HTTPS)
- 443/tcp     HTTPS (public or LAN depending on design)

### nexus-core (internal by default)
- 22/tcp      SSH (LAN only)
- 5678/tcp    n8n (bind to localhost; expose only via edge reverse proxy if needed)
- 5432/tcp    Postgres (docker network / localhost only)
- 6379/tcp    Redis (docker network / localhost only)
- 18789/tcp   OpenClaw Gateway/UI (bind to localhost; admin via SSH tunnel)

---

## Admin-only tunnel examples (high ports on your laptop)

These are **examples** for your local machine (macOS/Linux).  
They do **not** change the actual service ports on `nexus-core`.

### OpenClaw UI via SSH tunnel
- Local (laptop): `localhost:19089` -> Core: `127.0.0.1:18789`
- Example:
  - `ssh -N -L 19089:127.0.0.1:18789 nexus-core-ops`
  - Open: `http://127.0.0.1:19089/#token=...`

### n8n UI via SSH tunnel
- Local (laptop): `localhost:15678` -> Core: `127.0.0.1:5678`
- Example:
  - `ssh -N -L 15678:127.0.0.1:5678 nexus-core-ops`
  - Open: `http://127.0.0.1:15678/`

---

## Exposing services (recommended)

- Expose **only** via `nexus-edge` reverse proxy with **SSO/2FA**.
- Keep core service ports bound to **localhost** and/or **internal Docker networks**.
- Prefer **SSH tunneling** for admin-only access (VNC, DB tools, OpenClaw UI, etc.).
