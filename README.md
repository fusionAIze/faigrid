# [![repo-safety](https://github.com/typelicious/fusionaize-nexus-labs/actions/workflows/repo-safety.yml/badge.svg)](https://github.com/typelicious/fusionaize-nexus-labs/actions/workflows/repo-safety.yml) [![Lint](https://github.com/typelicious/fusionaize-nexus-labs/actions/workflows/lint.yml/badge.svg)](https://github.com/typelicious/fusionaize-nexus-labs/actions/workflows/lint.yml) [![Test](https://github.com/typelicious/fusionaize-nexus-labs/actions/workflows/test.yml/badge.svg)](https://github.com/typelicious/fusionaize-nexus-labs/actions/workflows/test.yml) [![Release](https://img.shields.io/github/v/release/typelicious/fusionaize-nexus-labs?display_name=tag)](https://github.com/typelicious/fusionaize-nexus-labs/releases) [![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
# [![OpenClaw-friendly](https://img.shields.io/badge/OpenClaw-friendly-111827.svg)](https://openclaw.ai/) [![n8n-automated](https://img.shields.io/badge/n8n-automated-ea4b71.svg?logo=n8n&logoColor=white)](https://n8n.io/) [![Docker-ready](https://img.shields.io/badge/docker-ready-2496ED?logo=docker&logoColor=white)](https://www.docker.com/) [![Bash-powered](https://img.shields.io/badge/Language-Bash-4EAA25.svg)](https://www.gnu.org/software/bash/)

## fusionAIze Nexus Labs

---

### Navigation
[Core Idea](#core-idea) • 
[Architecture](#architecture) • 
[Quick Start](#quick-start) • 
[Troubleshooting](#troubleshooting) • 
[Modules](#modules) • 
[Repository Layout](#repository-layout) • 
[License](#license)

---

## Quick Start

Get your Nexus infrastructure live in 2 steps:

```bash
# 1. Clone & Provision (Detects macOS/Linux automatically)
git clone https://github.com/typelicious/fusionaize-nexus-labs.git nexus
cd nexus && bash install.sh

# 2. Deploy your first node (e.g. Core Workbench)
./install.sh --mode local --role core --strategy 1 --yes
```

Done. Your AI Workbench is now accessible via the **Terminal Dashboard**:
```bash
./scripts/nexus-dashboard.sh
```

---

## Troubleshooting

If something feels off, run the **Nexus Doctor**. It performs comprehensive sanity checks on resources, connectivity, and local state:

```bash
./scripts/nexus-doctor.sh
```

To view live system telemetry and consolidated logs:
```bash
tail -f /var/log/nexus/nexus-system.log
```

## Core Idea

**fusionAIze Nexus Labs** is an open-source, modular reference stack designed for building self-hosted, sovereign **Agent & Automation** environments. It embraces a strict "deny-by-default" security philosophy, decoupling untrusted ingress (Edge) from critical orchestration (Core) and heavy LLM inference (Workers).

Rather than relying on heavy, black-box frameworks, Nexus Labs utilizes pure Bash orchestration, robust Systemd services, and well-understood Docker topologies to provide a transparent and resilient AI workbench.

---

## Architecture

The infrastructure relies on a decoupled, secure **4+1 Node Architecture**:

```text
                     Public Internet
                            │ (HTTPS)
      ┌─────────────────────▼─────────────────────┐
      │               NEXUS EDGE                  │ (1) Ingress / Proxy
      │     (Caddy Reverse Proxy, SSO, Auth)      │
      └─────────────────────┬─────────────────────┘
                            │ (Internal TLS)
      ┌─────────────────────▼─────────────────────┐
      │               NEXUS CORE                  │ (2) Orchestrator 
      │    (n8n, OpenClaw, RTK, Postgres, Redis)  │
      └──────┬─────────────────────────────┬──────┘
             │ (Local API)                 │ (Encrypted Tunnels)
  ┌──────────▼──────────┐       ┌──────────▼──────────┐
  │    NEXUS WORKER     │       │   NEXUS EXTERNAL    │ (5) Global Extension
  │  (Local LLM Nodes)  │       │  (Cloud VPS Node)   │
  └─────────────────────┘       └─────────────────────┘
             │
  ┌──────────▼──────────┐
  │    NEXUS BACKUP     │ (4) Offsite Storage
  │ (Synology / Restic) │
  └─────────────────────┘
```

---

## Modules

The Nexus framework is logically segmented into specialized operational roles:

- **nexus-edge**: The gatekeeper. Handles TLS termination (Caddy), CrowdSec bouncers, and identity providers (Authelia/Authentik). Exposed to the internet.
- **nexus-core**: The orchestrator. Contains the AI Workbench including n8n, further AI routing logic natively managed by OpenClaw, Redis distributed queues, and system telemetry watchdogs. Strictly internal.
- **nexus-worker**: The execution engine. Dedicated hardware running local LLMs (e.g., LM Studio/Ollama) routed securely to the Core via Tailscale or reverse SSH tunnels.
- **nexus-backup**: The safety net. Automated, immutable offline backup pipelines targeting dedicated local network attached storage.
- **nexus-external** *(optional)*: The global bridge. Distributed extension nodes for public-facing automated workflows (n8n) and project management (Plane.so), syncing back to the primary local grid.

> **Security Note:** This repository is intrinsically designed for autonomous deployments. It utilizes dynamic state and `.env.topology` generation. **Never commit secrets**.

---

## Repository Layout

- `core/` — Docker compose stacks, systemd servers, and core orchestration scripts.
- `docs/` — Core architecture design, example deployment grids, AI schemas, and tunneling runbooks.
- `edge/` — Firewall configs, advanced proxy templates, and SSO structures for Edge nodes.
- `scripts/` — The master orchestration utilities (`install.sh`, `nexus-deploy.sh`, `nexus-dashboard.sh`, `nexus-watchdog.sh`, `nexus-doctor.sh`).
- `tests/` — Automated syntactical checks and integration pipelines natively hooked into CI/CD.

---

### Support

If you find this engineering blueprint valuable or you're using it to bootstrap your own sovereign AI networks, please consider giving it a ⭐️ to help the community grow!

---

## License

Apache 2.0 — see [LICENSE](LICENSE) for details.

---

> Made with ❤️ in Berlin
