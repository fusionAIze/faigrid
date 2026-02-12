# Ports (reference)

This is a **generic reference** for the FusionAIze Nexus Labs architecture.
Do **not** put real public domains, IPs, or secret endpoints here.

## nexus-edge (example)
- 22/tcp    SSH (LAN only)
- 53/tcp+udp  DNS (LAN only; Pi-hole if used)
- 80/tcp    HTTP (optional; usually for ACME / redirect to HTTPS)
- 443/tcp   HTTPS (public or LAN depending on design)

## nexus-core (core heart, internal by default)
- 22/tcp    SSH (LAN only)
- 5678/tcp  n8n (internal only; bind to localhost on core)
- 5432/tcp  Postgres (internal only; docker network / localhost)
- 6379/tcp  Redis (internal only; docker network / localhost)
- 3000/tcp  OpenClaw (example; internal only; bind to localhost)

## Exposing services (recommended)
- Expose **only** via `nexus-edge` (reverse proxy) with **SSO/2FA**
- Keep core services bound to **localhost** and/or **internal Docker networks**
- Prefer **SSH tunneling** for admin-only access (e.g., VNC, DB tools)
