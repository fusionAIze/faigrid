# fusionAIze Nexus Labs — Architecture

fusionAIze Nexus Labs is a modular reference stack for running a secure, self-hosted **agent + automation** environment.

The architecture is organized around **roles** (what a node does), not specific hardware (what a node is).
Any role can run on many types of hosts (Raspberry Pi, mini PC, VM, VPS, cloud).

## Design principles

- **Least privilege**: split ingress, orchestration, execution, and storage. Every internal service runs under its own non-root system user.
- **Deny-by-default**: only the edge is exposed; core stays private.
- **Secrets never in Git**: use env templates + a secret store.
- **Service User Isolation**: Managed services (e.g., OpenClaw, future plugins) must use dedicated system users (`--system --shell /usr/sbin/nologin`) to prevent lateral movement in case of a compromise.
- **Modular & Versatile**: optimized for on-prem (LAN), private cloud (VPS), and public cloud (Hybrid) through role-based orchestration and configurable bind IPs.
- **Observable & recoverable**: real-time metrics/logs + Restic-based "Time Machine" backups + interactive restore runbooks.
- **Universal Lifecycle API**: every module (Core, Edge, Worker, Backup) follows a standardized script pattern (`install`, `update`, `uninstall`, `verify`, `control`).

## Roles (hardware-agnostic)

### 1) nexus-edge (ingress + optional LAN DNS)

Responsibilities:
- TLS termination + reverse proxy (Caddy/Traefik/Nginx)
- optional LAN DNS / ad-blocking (Pi-hole / AdGuard Home)
- optional SSO/2FA gate (Authelia/Authentik)
- optional abuse protection (CrowdSec)
- firewall baseline

Typical exposure:
- 80/443 (ingress)
- 53 (DNS, LAN-only if enabled)
- 22 (SSH, LAN-only)

### 2) nexus-core (orchestrator + AI Workbench)

Responsibilities:
- Internal n8n (automation backbone, not exposed externally)
- OpenClaw (agent orchestrator / dispatcher)
- Routing Layer (FoundryGate, RTK, ICM) for model token-consumption and memory routing
- Workbench Tooling (CLIs like kilo, gemini, claude, codex, paperclip, ship-faster)
- State & Queue (Postgres + Redis)

Typical exposure:
- ideally **not** exposed directly; accessed via `nexus-edge` reverse proxy Layer or VPN

### 3) nexus-worker (LLM execution backend)

Responsibilities:
- local model serving (LM Studio / Ollama / vLLM) and/or routing to cloud LLMs
- access restricted to LAN/VPN and allowlisted callers (e.g., `nexus-core`)
- cost-optimized coding/review tasks and offline/low-cost inference

Typical exposure:
- LAN/VPN only (HTTP API)

### 4) nexus-backup (backup target)

Responsibilities:
- backup target for configs, DB dumps, and artifacts
- retention policies + optional immutability (WORM) and offsite replication
- regular restore tests

Targets can be:
- NAS, external disk, S3-compatible object storage, rsync target, etc.

### 5) nexus-external (public cloud extension)

Responsibilities:
- Hosting external-facing collaboration tools (e.g. Agency-PM / Plane)
- External Workflow Automation (external-n8n)
- Securely communicating inward with the internal `nexus-core` n8n

Typical exposure:
- Publicly accessible via internet (Standard web ports 80/443)

## Recommended Network Architecture (LAN)

For a standard 4+1 home or lab deployment, we recommendation assigning static IPs (reserved in your router/FritzBox/Switch) to ensure consistent connectivity between nodes:

| Node | Role | Recommended IP |
|---|---|---|
| **nexus-edge** | Ingress, DNS, TLS | `192.168.178.10` |
| **nexus-core** | AI Workbench, n8n | `192.168.178.20` |
| **nexus-worker** | LLM Inference (Mac, GPU) | `192.168.178.30` |
| **nexus-backup** | Restic Vault, NAS | `192.168.178.40` |
| **nexus-external** | Cloud PM, External n8n | *Cloud Dynamic / Public IP* |

> [!TIP]
> Use these IPs to pre-configure your `.env.topology` or simply follow the prompts in `install.sh`.

## Execution model (recommended)

- Webhooks enter via **nexus-edge** or **nexus-external**
- Workflows run in **n8n** on **nexus-core**
- Routing and model dispatching runs via **FoundryGate/RTK**
- Actions execute via isolated runner CLIs (codex, paperclip) or **OpenClaw** agents
- Everything is logged and backed up

## Roadmap modules (extensions)

- SSO/2FA (Authelia/Authentik) before n8n
- CrowdSec bouncers integrated with reverse proxy
- Redis-backed queue mode and worker runners
- Observability stack (Prometheus + Grafana + Loki)
- RAG per project (Qdrant/pgvector)
- GitOps deployment workflows

## Architectural Scale & Examples

Because this architecture separates functional **roles** from underlying **hardware**, it ranges from a simple DIY homelab to a multi-region cloud deployment.

For concrete infrastructure mapping examples (e.g., *Local Agency Lab* vs. *Full Cloud Deployment*), refer to:
- [`docs/example_setups.md`](example_setups.md)
