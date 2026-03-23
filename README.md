# fusionAIze Grid (faigrid)

[![repo-safety](https://github.com/fusionAIze/faigrid/actions/workflows/repo-safety.yml/badge.svg)](https://github.com/fusionAIze/faigrid/actions/workflows/repo-safety.yml) [![Lint](https://github.com/fusionAIze/faigrid/actions/workflows/lint.yml/badge.svg)](https://github.com/fusionAIze/faigrid/actions/workflows/lint.yml) [![Test](https://github.com/fusionAIze/faigrid/actions/workflows/test.yml/badge.svg)](https://github.com/fusionAIze/faigrid/actions/workflows/test.yml) [![Release](https://img.shields.io/github/v/release/fusionAIze/faigrid?display_name=tag)](https://github.com/fusionAIze/faigrid/releases) [![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OpenClaw-friendly](https://img.shields.io/badge/OpenClaw-friendly-111827.svg)](https://openclaw.ai/) [![n8n-automated](https://img.shields.io/badge/n8n-automated-ea4b71.svg?logo=n8n&logoColor=white)](https://n8n.io/) [![Docker-ready](https://img.shields.io/badge/docker-ready-2496ED?logo=docker&logoColor=white)](https://www.docker.com/) [![Bash-powered](https://img.shields.io/badge/Language-Bash-4EAA25.svg)](https://www.gnu.org/software/bash/)

> **The sovereign execution substrate for AI-native operations.**

**fusionAIze Grid (faigrid)** is the execution substrate of the fusionAIze ecosystem. Its explicit job is to define **where** AI-native work runs, under **what constraints**, with **what isolation**, through which **queues and runners**, and with which **observability and recovery patterns**.

It provides a modular, secure, and self-hosted foundation across local, on-prem, private cloud, public cloud, and hybrid deployments.

---

### Navigation
[The Ecosystem](#the-ecosystem) • 
[Architecture](#architecture) • 
[Quick Start](#quick-start) • 
[Troubleshooting](#troubleshooting) • 
[Grid Modules](#grid-modules) • 
[Repository Layout](#repository-layout) • 
[License](#license)

---

## The Ecosystem

`faigrid` is part of a 5-layer product architecture that operationalizes human-AI fusion teams:
1. **Gate (`faigate`)**: AI-native gateway for models, providers, tools and clients. *(Connects)*
2. **Lens**: Compression, translation, and context-focusing layer. *(Filters)*
3. **Fabric**: Shared context and memory. *(Remembers & Serves)*
4. **Grid (`faigrid`)**: This repository. The sovereign execution substrate. *(Executes)*
5. **OS (`fusionAIzeOS`)**: The operating logic defining how humans and virtual AI coworkers collaborate. *(Orchestrates Logic)*

### Core Philosophy
- **Execution First**: We define rigorous *Execution Classes* (Edge, Internal, Queued, Runners, Local Workers) rather than fuzzy environments.
- **Agent Agnostic**: We provide the raw OS execution substrate agnostic of the framework (OpenClaw, AutoGen, CrewAI).
- **Macher-Fokus (Builder Focus)**: Designed originally for the **Solo Operator** and scalable to **Small Teams** and **SMBs** without enterprise compliance theater.
- **Portability**: Full freedom to run proprietary SaaS routes (via Cloud Bridges) or fully local open-source operations (via Local Model Workers).

---

## Architecture

The infrastructure relies on a decoupled, secure **4+1 Node Architecture**:

```text
                      Public Internet
                             │ (HTTPS)
       ┌─────────────────────▼─────────────────────┐
       │               GRID EDGE                   │ (1) Ingress / Proxy
       │     (Caddy Reverse Proxy, SSO, Auth)      │
       └─────────────────────┬─────────────────────┘
                             │ (Internal TLS)
       ┌─────────────────────▼─────────────────────┐
       │               GRID CORE                   │ (2) Trusted Internal Services
       │    (n8n, OpenClaw, RTK, Postgres, Redis)  │     / Queued Automations
       └──────┬─────────────────────────────┬──────┘
              │ (Local API)                 │ (Encrypted Tunnels)
   ┌──────────▼──────────┐       ┌──────────▼──────────┐
   │    GRID WORKER      │       │   GRID EXTERNAL     │ (5) Cloud Model Bridges
   │  (Local LLM Nodes)  │       │  (Cloud VPS Node)   │     / Global Extension
   └─────────────────────┘       └─────────────────────┘
              │
   ┌──────────▼──────────┐
   │    GRID BACKUP      │ (4) Observability & 
   │ (Synology / Restic) │     Recovery Base
   └─────────────────────┘
```

---

## Quick Start

Get your faigrid ecosystem live in 2 steps:

```bash
# 1. Clone & Provision (Detects macOS/Linux automatically)
git clone https://github.com/fusionAIze/faigrid.git faigrid
cd faigrid && bash install.sh

# 2. Deploy your first node (e.g. Core Runtime)
./install.sh --mode local --role core --strategy 1 --yes
```

Done. Your AI execution substrate is now accessible via the **Terminal Dashboard**:
```bash
./scripts/grid-dashboard.sh
```

---

## Troubleshooting

If something feels off, run the **Grid Doctor**. It performs comprehensive sanity checks on resources, connectivity, and local state:

```bash
./scripts/grid-doctor.sh
```

To view live system telemetry and consolidated logs:
```bash
tail -f /var/log/faigrid/grid-system.log
```

---

## Grid Modules

The faigrid framework segments execution classes into specialized operational roles:

- **grid-edge**: The gatekeeper. Handles TLS termination (Caddy), CrowdSec bouncers, and identity intake. Public-facing but tightly constrained.
- **grid-core**: The private compute substrate. Hosts internal services (n8n), queue consumers, internal APIs, and stable coordination. Strictly internal.
- **grid-worker**: Dedicated isolated execution workers. Examples include local inference (LM Studio/Ollama), review workers, and shell runners routed securely to the Core.
- **grid-backup**: The safety net. Automated, immutable offline backup pipelines targeting dedicated local network attached storage.
- **grid-external** *(optional)*: Cloud model bridges for access to external hosted workloads under strict egress-aware constraints.

> **Security Note:** This repository is intrinsically designed for autonomous deployments. It utilizes dynamic state and `.env.topology` generation. **Never commit secrets**.

---

## Repository Layout

- `core/` — Docker compose stacks, systemd servers, and core execution scripts.
- `docs/` — Core architecture roadmap, example deployment profiles (Solo to SMB), runbooks.
- `edge/` — Firewall configs, advanced proxy templates, and SSO entry structures.
- `scripts/` — The master orchestration utilities (`install.sh`, `grid-dashboard.sh`, `grid-watchdog.sh`, `grid-doctor.sh`).
- `tests/` — Automated syntactical checks (Bats-core) natively hooked into CI/CD.

---

### Support

If you find this engineering blueprint valuable or you're using it to bootstrap your own sovereign AI networks, please consider giving it a ⭐️ to help the community grow!

---

## License

Apache 2.0 — see [LICENSE](LICENSE) for details.

---

> Made with ❤️ in Berlin
