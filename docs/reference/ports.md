# Ports (reference)

## nexus-edge (example)
- 22/tcp  SSH (LAN only)
- 53/tcp+udp DNS (LAN only)
- 80/443  HTTP/HTTPS (LAN or public depending on design)

## nexus-core (core heart, internal by default)
- 22/tcp  SSH (LAN only)
- 5678    n8n (internal only; behind reverse proxy if exposed)
- 5432    Postgres (internal only)
- 6379    Redis (internal only)
- 3000    OpenClaw (example; internal only)

## Exposing services
Recommendation:
- Expose **only** through a reverse proxy with SSO/2FA (edge)
- Keep service ports bound to localhost or internal docker network
