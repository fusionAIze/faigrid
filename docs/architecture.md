# fusionAIze Nexus Labs — Architecture

fusionAIze Nexus Labs is a modular reference stack for running a secure, self-hosted **agent + automation** environment.

The architecture is organized around **roles** (what a node does), not specific hardware (what a node is).
Any role can run on many types of hosts (Raspberry Pi, mini PC, VM, VPS, cloud).

## Design principles

- **Least privilege**: split ingress, orchestration, execution, and storage.
- **Deny-by-default**: only the edge is exposed; core stays private.
- **Secrets never in Git**: use env templates + a secret store.
- **Modular**: supports on-prem, private cloud, public cloud, and hybrid deployments.
- **Observable & recoverable**: metrics/logs + backups + restore runbooks.
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
