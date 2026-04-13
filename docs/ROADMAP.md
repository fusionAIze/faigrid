# Roadmap — fusionAIze Grid

## Vision

**fusionAIze Grid is the sovereign execution substrate for AI-native operations.**

Its job is to define *where* AI-native work runs, under *what constraints*, with *what isolation*, through which *queues and runners*, and with which *observability and recovery patterns*.

Grid is the execution layer. It does not do context, memory, or routing — those belong to Fabric, Gate, and Lens. What Grid uniquely provides is the hardened, portable, self-hosted infrastructure that makes the rest of the fusionAIze stack actually run.

---

## Guiding Principles

- **Execution First** — strict Execution Classes over fuzzy environments
- **Solo-to-SMB** — scales from a single operator to a small team without enterprise theater
- **Builder Focus** — predictable Bash, clear state, zero hidden magic
- **Signal-Ready** — emit clean runtime signals that faisignal can consume without coupling
- **Security by Default** — deny-at-edge, internal-only core, secrets never in Git

---

## Stack Position

| Layer | Repo | Relationship to Grid |
|---|---|---|
| Gate | `faigate` | Routes AI requests through Grid's core services |
| Lens | `failens` | Context layer — future integration via core API |
| Fabric | `faifabric` | Memory layer — future integration via core API |
| **Grid** | `faigrid` ← | Execution substrate |
| Signal | `faisignal` | Consumes Grid's runtime health and event signals |
| OS | `fusionAIzeOS` | Injects role-aware collaboration logic into Grid runners |

---

## Current State — v1.6.1

### What exists and works

**4+1 Node Architecture (install.sh orchestrator)**
- `grid-edge`: Caddy reverse proxy, Pi-hole DNS, internal `.grid` TLD, TLS-internal
- `grid-core`: n8n, openclaw, codenomad, faigate, grid-messenger, Postgres, Redis
- `grid-worker`: Ollama, LM Studio, shell runners
- `grid-backup`: Restic, Synology
- `grid-external`: Cloud model bridges

**Grid Workbench** — interactive operator console with plugin registry
- Plugins: n8n, openclaw, codenomad, faigate, caddy, grid-messenger
- Standard plugin interface: `tool_configure` · `tool_doctor` · `tool_update`
- Projects manager (`_projects.sh`) — git repo management on nodes
- Skills deployer (`_skills.sh`) — AI skill import and cross-agent deployment

**Grid Messenger** — Telegram decision and notification bridge
- Three decision types: `approve` / `choice` / `input`
- App registry with emoji, display name, Telegram topic thread routing
- HTTP API on `127.0.0.1:9119` — any core service can push decisions or notifications

**CI / Quality**
- ShellCheck, ruff, bats smoke tests, CodeQL, repo-safety
- Pre-commit hooks: shellcheck, ruff, conventional commits, version-consistency
- release-please automated versioning + Homebrew tap dispatch

---

## Phase 1 — Signal Readiness (v1.7 – v1.9)

*Make Grid's runtime state observable by faisignal.*

faisignal's roadmap explicitly expects Grid to emit:
- runner failures and retry spikes
- queue backlog anomalies
- job-completion degradation
- local/cloud worker imbalance
- service-level health per node

### Deliverables

**`/api/v1/health` endpoint** (grid-core, `127.0.0.1:9120`)
- Node reachability (edge, core, worker, backup, external)
- Service status per node (n8n, openclaw, faigate, messenger, caddy)
- Last-seen timestamps

**`/api/v1/events` stream** (WebSocket or SSE)
- Structured event objects: `ServiceEvent`, `NodeEvent`, `RunnerEvent`
- Fields: `type`, `node`, `service`, `status`, `timestamp`, `detail`
- Consumed by faisignal without any Grid-specific coupling

**Grid Watchdog hardening**
- Emit structured JSON events on state changes to `grid-system.log`
- Log format aligned with faisignal's `log_ingestor` plugin contract

**Grid Doctor signals**
- Machine-readable `--json` output flag for programmatic health checks

---

## Phase 2 — Operator Cockpit (v2.0)

*Ship the Grid operator dashboard — faigate-inspired, Grid-scoped.*

The cockpit is a **lightweight, no-build Python-served HTML dashboard** running on `grid-core`. Design language inherits from faigate's cockpit (dark navy, 280px sticky left rail, card-based panels) but all sections answer Grid-specific operator jobs.

### Cockpit Sections

| Section | Operator Job |
|---|---|
| **Overview** | "Is my Grid healthy and ready right now?" |
| **Nodes** | "Which nodes are reachable and what are they running?" |
| **Services** | "Which services are up, degraded, or missing?" |
| **Messenger** | "What decisions are pending? What just happened?" |
| **Workbench** | "Which plugins are installed? What needs updating?" |
| **Signals** | "What events has Grid emitted recently?" |
| **Setup** | "How do I add a node or configure a new service?" |

See `docs/COCKPIT.md` for the full information architecture and design spec.

### Technical shape
- Python + aiohttp, served alongside grid-messenger or as a separate systemd unit
- Inline HTML — single-file, no npm, no bundler
- Reads from `/api/v1/health` and `grid-messenger`'s `/health` endpoint
- WebSocket live-reload for service status cards

---

## Phase 3 — Execution Classes & GitOps (v2.1 – v2.5)

*Formalize runner discipline and declarative topology.*

- **Queue & Runner discipline** — explicit runner boundaries (Browser Runners, Shell Runners, Privileged Runners) with queue depth monitoring
- **GitOps topology** — declarative `topology.yaml` that describes the 4+1 layout and can be applied idempotently
- **Hybrid model bridging** — seamless orchestration between Cloud Bridges (via faigate) and Local Workers (via grid-worker)
- **Deployment Profile templates** — `Solo Operator` → `Small Team` → `SMB` starter configs with documented migration paths

---

## Phase 4 — fusionAIzeOS Integration (v3.x)

*Role-aware collaboration logic injected into Grid runners.*

- Grid runners receive role context from OS (who is allowed to run what, under which policy)
- Escalation and override events surface in Signal's collaboration signals family
- Identity-aware audit log for Grid execution events
- Policy-gated runner classes (e.g., Privileged Runners require explicit OS approval)

---

## What Grid Deliberately Does Not Do

- **Model routing** — that is Gate's job
- **Context or memory management** — that is Lens/Fabric's job
- **Operating logic / team coordination** — that is fusionAIzeOS's job
- **Enterprise compliance theater** — Grid stays lean and operator-owned
- **Complex analytics or BI dashboards** — Signal handles cross-layer observability

---

## Versioning Convention

Grid follows semantic versioning via `release-please`:
- **Patch** (`x.y.Z`) — bug fixes, doc updates, minor polish
- **Minor** (`x.Y.0`) — new features, new plugins, new API surfaces
- **Major** (`X.0.0`) — explicit breaking changes with documented migration

Current version tracked in `VERSION` and `install.sh:INSTALL_VERSION`.
