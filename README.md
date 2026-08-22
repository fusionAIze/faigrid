# fusionAIze Grid (faigrid)

[![repo-safety](https://github.com/fusionAIze/faigrid/actions/workflows/repo-safety.yml/badge.svg)](https://github.com/fusionAIze/faigrid/actions/workflows/repo-safety.yml)
[![Lint](https://github.com/fusionAIze/faigrid/actions/workflows/lint.yml/badge.svg)](https://github.com/fusionAIze/faigrid/actions/workflows/lint.yml)
[![Test](https://github.com/fusionAIze/faigrid/actions/workflows/test.yml/badge.svg)](https://github.com/fusionAIze/faigrid/actions/workflows/test.yml)
[![Release](https://img.shields.io/github/v/release/fusionAIze/faigrid?display_name=tag)](https://github.com/fusionAIze/faigrid/releases)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OpenClaw-friendly](https://img.shields.io/badge/OpenClaw-friendly-111827.svg)](https://openclaw.ai/)
[![n8n-automated](https://img.shields.io/badge/n8n-automated-ea4b71.svg?logo=n8n&logoColor=white)](https://n8n.io/)
[![Docker-ready](https://img.shields.io/badge/docker-ready-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![Bash-powered](https://img.shields.io/badge/Language-Bash-4EAA25.svg)](https://www.gnu.org/software/bash/)

> **The sovereign execution substrate for AI-native operations.**

**fusionAIze Grid** defines *where* AI-native work runs, under *what constraints*, with *what isolation*, through which *queues and runners*, and with which *observability and recovery patterns*. It is the execution layer of the fusionAIze ecosystem — not the context, memory, or routing layer.

---

### Navigation

[Ecosystem](#the-ecosystem) •
[Architecture](#architecture) •
[Quick Start](#quick-start) •
[Grid Modules](#grid-modules) •
[Workbench](#workbench-plugins) •
[Messenger](#grid-messenger) •
[Repository Layout](#repository-layout) •
[Troubleshooting](#troubleshooting) •
[License](#license)

---

## The Ecosystem

`faigrid` is part of the fusionAIze 5-layer product architecture that operationalizes human-AI fusion teams:

| Layer | Repo | Role |
|---|---|---|
| **Gate** | `faigate` | AI-native gateway for models, providers, tools and clients |
| **Lens** | `failens` | Compression, translation, and context-focusing |
| **Fabric** | `faifabric` | Shared context, memory, and knowledge |
| **Grid** | `faigrid` ← | Sovereign execution substrate |
| **Signal** | `faisignal` | Observability, monitoring, and signal layer |
| **OS** | `fusionAIzeOS` | Operating logic for human-AI fusion teams |

faigrid feeds **runtime health signals** (runner failures, service state, queue backlog, job completion) directly into fusionAIze Signal for cross-layer operational intelligence.

---

## Architecture

The infrastructure relies on a decoupled, secure **4+1 Node Architecture**:

```
                     Public Internet
                            │ (HTTPS)
      ┌─────────────────────▼─────────────────────┐
      │               GRID EDGE                   │  (1) Ingress / Proxy
      │   Caddy Reverse Proxy · Pi-hole DNS · SSO │
      └─────────────────────┬─────────────────────┘
                            │ (Internal TLS / .grid)
      ┌─────────────────────▼─────────────────────┐
      │               GRID CORE                   │  (2) Trusted Internal Services
      │  n8n · openclaw · codenomad · faigate     │
      │  grid-messenger · Postgres · Redis        │
      └──────┬─────────────────────────────┬──────┘
             │ (Local API)                 │ (Encrypted Tunnels)
  ┌──────────▼──────────┐       ┌──────────▼──────────┐
  │    GRID WORKER      │       │   GRID EXTERNAL     │  (5) Cloud Model Bridges
  │  Local LLM · Ollama │       │   Cloud VPS Node    │
  └──────────┬──────────┘       └─────────────────────┘
             │
  ┌──────────▼──────────┐
  │    GRID BACKUP      │  (4) Observability & Recovery
  │  Synology · Restic  │
  └─────────────────────┘
```

**Execution Classes** — Grid's core abstraction:

| Class | Where | What |
|---|---|---|
| Edge Ingress | grid-edge | TLS termination, reverse proxy, DNS, auth |
| Trusted Internal | grid-core | n8n, APIs, orchestration, messaging |
| Queued Automations | grid-core | Workflow engine, background tasks |
| Local Model Workers | grid-worker | Ollama, LM Studio, LAN-only inference |
| Cloud Model Bridges | grid-external | Egress-controlled cloud reasoning |
| Recovery Base | grid-backup | Automated immutable backup pipelines |

---

## Quick Start

```bash
# Clone and provision (detects macOS/Linux automatically)
git clone https://github.com/fusionAIze/faigrid.git && cd faigrid
bash install.sh

# Deploy a specific role, e.g. Core
./install.sh --mode local --role core --strategy 1 --yes
```

**Flags:**

- `--yes` auto-confirms **non-destructive** prompts (role selection, mode, VNC, reinstall-over-nothing, etc.).
- `--force` bypasses **destructive** overwrite/wipe prompts.
- The uninstall `delete-all-data` confirmation is **always** required verbatim — no flag bypasses it.

Node registry is stored at `~/.config/faigrid/registry/` and persists across reinstalls and Homebrew upgrades.

```bash
# Open the interactive Workbench
./core/workbench/scripts/control.sh

# Run diagnostics
./scripts/grid-doctor.sh

# Check live logs
tail -f /var/log/faigrid/grid-system.log
```

---

## Grid Modules

| Module | Role | Services |
|---|---|---|
| **grid-edge** | Public gatekeeper | Caddy, Pi-hole, CrowdSec, SSO |
| **grid-core** | Private compute substrate | n8n, openclaw, codenomad, faigate, grid-messenger |
| **grid-worker** | Isolated execution | Ollama, LM Studio, shell runners |
| **grid-backup** | Safety net | Restic, Synology, automated snapshots |
| **grid-external** | Cloud bridge | Egress-aware VPS, external model access |

---

## Workbench Plugins

The **Grid Workbench** (`core/workbench/`) is the interactive operator console for managing services on each node. Plugins are self-contained Bash modules with a standard interface (`tool_configure`, `tool_doctor`, `tool_update`).

**Current plugin registry:**

| Plugin | Category | Purpose |
|---|---|---|
| `n8n` | automation | Workflow engine — install, configure, manage |
| `openclaw` | agents | OpenClaw agent runtime — deploy, update, doctor |
| `codenomad` | agents | Codenomad coding agent — configure, manage |
| `faigate` | gateway | fusionAIze Gate — install, configure, health |
| `caddy` | proxy | Internal LAN reverse proxy — `.grid` TLD + Pi-hole DNS |
| `grid-messenger` | comms | Telegram decision bridge — configure, health |

Plugin categories: `agents/` · `automation/` · `proxy/` · `comms/`

---

## Grid Messenger

`grid-messenger` is the **Telegram decision and notification bridge** for the Grid. It runs as a systemd service on grid-core and exposes a local HTTP API (`127.0.0.1:9119`) that any registered app (n8n, openclaw, codenomad, etc.) can call to push decisions or notifications.

**Three decision types:**

| Type | UI | Use case |
|---|---|---|
| `approve` | Approve / Reject buttons | Binary gate — deploy, merge, confirm |
| `choice` | N labelled buttons | Multi-option selection — which agent, which branch |
| `input` | Free-text capture | User-supplied values — target dir, config input |

**App registry** — each app (openclaw, codenomad, n8n, …) registers with a display name, emoji, and optional Telegram topic thread ID for sub-channel routing.

```bash
# HTTP API (from any app on grid-core)
POST http://127.0.0.1:9119/decision/request
POST http://127.0.0.1:9119/notify
POST http://127.0.0.1:9119/app/register
GET  http://127.0.0.1:9119/health
```

See `core/messenger/` for installation and configuration details.

---

## Repository Layout

```
faigrid/
├── install.sh                    # Root orchestrator (state-aware)
├── core/
│   ├── workbench/
│   │   └── scripts/
│   │       ├── control.sh        # Interactive Workbench CLI
│   │       ├── _lib.sh           # Shared helpers
│   │       ├── _projects.sh      # Project/repo manager
│   │       ├── _skills.sh        # AI skill deployer
│   │       └── plugins/
│   │           ├── agents/       # openclaw, codenomad
│   │           ├── automation/   # n8n
│   │           ├── proxy/        # caddy
│   │           └── comms/        # grid-messenger
│   └── messenger/
│       ├── src/grid_messenger.py # Telegram bot service
│       ├── install.sh            # Messenger installer
│       ├── systemd/              # Service unit
│       └── requirements.txt
├── docs/
│   ├── ROADMAP.md
│   ├── IMPLEMENTATION-PLAN.md
│   ├── architecture/
│   ├── runbooks/
│   └── reference/
├── scripts/
│   ├── grid-doctor.sh
│   ├── grid-dashboard.sh
│   ├── grid-deploy.sh
│   ├── grid-watchdog.sh
│   └── faigrid-release
├── tests/
│   └── smoke/
└── .github/
    └── workflows/                # lint, test, release-please, codeql, repo-safety
```

---

## Troubleshooting

```bash
# Comprehensive health check
./scripts/grid-doctor.sh

# Live system log
tail -f /var/log/faigrid/grid-system.log

# Workbench plugin doctor (per-service)
./core/workbench/scripts/control.sh doctor
```

Common issues:

| Symptom | Cause | Fix |
|---|---|---|
| `no registered nodes` after Homebrew install | OLD: registry was repo-relative | Registry migrated to `~/.config/faigrid/registry/` in v1.6.0 |
| `.grid` domains not resolving | Pi-hole DNS not set as resolver | Set workstation DNS to Edge LAN IP |
| `grid-messenger` decisions not arriving | Bot token or chat ID missing | Run Workbench → comms → grid-messenger → configure |

---

## Security

- All core services bind to `127.0.0.1` — never exposed beyond localhost/LAN without explicit edge config.
- Secrets live in `.env` files outside the repo. Never committed. `.gitignore` covers all credential patterns.
- Services run as dedicated system users (no login shell, no home dir). See `CLAUDE.md` for the full system user pattern.
- Destructive operations (uninstall, wipe, volume removal) always prompt for confirmation.

---

## License

Apache 2.0 — see [LICENSE](LICENSE) for details.

---

> Made with ❤️ in Berlin · Part of the [fusionAIze](https://github.com/fusionAIze) ecosystem

## Repository & Contributing

Canonical repository: **self-hosted Forgejo** — `git.langevc.com/fusionaize/faigrid`
(`git clone git@git.langevc.com:fusionaize/faigrid.git`). Develop against the Forgejo
clone and open pull requests there. The GitHub copy is a read-only mirror.
