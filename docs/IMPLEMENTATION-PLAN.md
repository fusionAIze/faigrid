# Implementation Plan — fusionAIze Grid

## Goal

Turn Grid's existing execution substrate into a **signal-ready, operator-observable platform** — one that feeds clean runtime data into fusionAIze Signal and gives operators a coherent cockpit for their Grid.

This plan is not a parking lot. It covers the two near-term release lines that move Grid from "working installation tool" to "observable execution substrate with operator dashboard".

---

## Current baseline (v1.6.1)

What exists and is working:

| Component | Status |
|---|---|
| `install.sh` orchestrator (state-aware, 4+1 node) | ✅ stable |
| Workbench + plugin registry (6 plugins) | ✅ stable |
| grid-messenger (Telegram, 3 decision types, app registry) | ✅ stable |
| Internal LAN proxy (Caddy + Pi-hole `.grid` TLD) | ✅ stable |
| CI: ShellCheck, ruff, bats, CodeQL, release-please | ✅ green |
| Pre-commit hooks: shellcheck, ruff, version-consistency | ✅ hooked |
| Homebrew tap distribution | ✅ live |
| Node registry at `~/.config/faigrid/registry/` | ✅ stable |

What is missing before the cockpit and Signal integration can ship:

| Gap | Needed for |
|---|---|
| No structured `/api/v1/health` endpoint | Cockpit, Signal ingestion |
| No structured event stream | Signal `log_ingestor` plugin |
| `grid-doctor.sh` output is human-only text | Programmatic health checks |
| No cockpit dashboard | Operator observability |
| `grid-messenger` not yet served via HTTP API for Grid state | Cockpit backend |

---

## Release line 1 — Signal Readiness (v1.7 – v1.9)

*Make Grid's runtime state consumable by faisignal without coupling.*

**Scope commitment**: No UI, no new user-facing features. Only structured data output.

### v1.7 — Health API

**New: `core/api/grid_health.py`**

Lightweight aiohttp service on `127.0.0.1:9120`.

```
GET /api/v1/health
```

Response shape:
```json
{
  "version": "1.7.0",
  "timestamp": "2026-...",
  "nodes": {
    "edge":     { "reachable": true,  "last_seen": "...", "services": ["caddy", "pihole"] },
    "core":     { "reachable": true,  "last_seen": "...", "services": ["n8n", "openclaw", "faigate", "messenger"] },
    "worker":   { "reachable": false, "last_seen": "...", "services": [] },
    "backup":   { "reachable": true,  "last_seen": "...", "services": ["restic"] },
    "external": { "reachable": false, "last_seen": null,  "services": [] }
  },
  "services": {
    "n8n":            { "node": "core", "status": "ok",   "port": 5678 },
    "openclaw":       { "node": "core", "status": "ok",   "port": 18789 },
    "faigate":        { "node": "core", "status": "ok",   "port": 8090 },
    "messenger":      { "node": "core", "status": "ok",   "port": 9119 },
    "caddy":          { "node": "edge", "status": "ok",   "port": 443 }
  }
}
```

Reads node registry from `~/.config/faigrid/registry/*.state`.
Performs lightweight TCP reachability probes (no SSH, no auth).

**Implementation notes:**
- Single Python file, Bash 3.2-safe installer
- Runs as `grid-health` system user (same isolation pattern as grid-messenger)
- Started alongside grid-messenger via systemd, or as a separate unit
- No external dependencies beyond Python stdlib + aiohttp

### v1.8 — Structured event log

**Update: `scripts/grid-watchdog.sh`**

Emit structured JSON lines to `/var/log/faigrid/grid-events.jsonl`:

```json
{ "type": "service_down", "node": "core", "service": "n8n", "at": "2026-...", "detail": "TCP probe failed" }
{ "type": "service_recovered", "node": "core", "service": "n8n", "at": "2026-...", "detail": "TCP probe OK" }
{ "type": "node_unreachable", "node": "worker", "at": "2026-...", "detail": "SSH timeout" }
```

Event types:
- `service_down` / `service_recovered`
- `node_unreachable` / `node_recovered`
- `decision_requested` / `decision_resolved` (from grid-messenger)
- `plugin_installed` / `plugin_updated`

faisignal's `log_ingestor` plugin can tail this file directly.

**Update: `scripts/grid-doctor.sh`**

Add `--json` flag for machine-readable output:
```bash
./scripts/grid-doctor.sh --json > /tmp/grid-health.json
```

### v1.9 — Signal integration test

- Document the faisignal collector config for faigrid (how to point `log_ingestor` at `/var/log/faigrid/grid-events.jsonl`)
- Document the `/api/v1/health` polling config for faisignal's `prometheus_scraper`
- Add a `docs/integrations/faisignal.md` integration guide

---

## Release line 2 — Operator Cockpit (v2.0)

*Ship a lightweight operator dashboard. faigate-inspired design, Grid-scoped content.*

### Design principles (from faigate DASHBOARD-IA.md, adapted for Grid)

1. **Jobs first, metrics second** — each section answers one operator question
2. **Confidence before detail** — Overview shows "is my Grid OK?" in one glance
3. **Read-only first** — cockpit is an observation surface; actions go through Workbench CLI
4. **Progressive disclosure** — overview stays compact; node/service detail pages go deep
5. **Signal-compatible** — cockpit sections map to faisignal's runtime health signal family

### Information architecture

#### 1. Overview
**Operator job**: "Tell me if my Grid is healthy and request-ready right now."

- Node status summary (edge / core / worker / backup / external) — colored badges
- Service health summary — count of healthy vs degraded vs unknown
- Pending decisions from grid-messenger (count + top item)
- Last event from grid-events.jsonl
- "Priority next" card — top issue detected, link to relevant section

#### 2. Nodes
**Operator job**: "Which nodes are reachable and what are they running?"

- One card per node (edge, core, worker, backup, external)
- Reachability status + last-seen timestamp
- Services list per node with inline status icons
- SSH target hint (derived from registry, never exposed as credential)

#### 3. Services
**Operator job**: "Which services are up, degraded, or stale?"

- Table: service name / node / port / status / last-checked
- Drilldown per service: recent log lines, health endpoint response
- Link to Workbench plugin for reconfiguration

#### 4. Messenger
**Operator job**: "What decisions are pending? What happened recently?"

- Live pending decision cards (type badge, source, description, time-in-queue)
- Recent resolved decisions (last 20)
- Registered apps list with last-active timestamp
- Direct link to Telegram bot

#### 5. Workbench
**Operator job**: "Which plugins are installed and what needs attention?"

- Plugin cards: name / category / installed version / update available
- Plugin status (configured / unconfigured / unhealthy)
- "Run doctor" quick-link per plugin

#### 6. Signals
**Operator job**: "What events has my Grid emitted recently?"

- Event timeline from `grid-events.jsonl`
- Filter by type: `service` / `node` / `decision` / `plugin`
- Tail mode (live updates via WebSocket)

#### 7. Setup
**Operator job**: "How do I add a node or configure a new service?"

- Node registration wizard (reads install.sh topology flags)
- Quick-start links for each Workbench plugin
- Link to `grid-doctor.sh` output

### Technical implementation

**File structure:**
```
core/cockpit/
├── grid_cockpit.py          # aiohttp server + WebSocket handler
├── dashboard_web.py         # Inline HTML (single-file, no build)
├── assets/
│   └── brand/               # SVG wordmark, favicon
├── install.sh               # Cockpit installer (system user, systemd unit)
└── systemd/
    └── grid-cockpit.service
```

**Stack:**
- Python 3.10+, aiohttp, same pattern as grid-messenger
- All CSS/JS inline in `dashboard_web.py` — no CDN, no npm
- Fonts: system stack (no custom fonts for v1)
- Live data via WebSocket on `/ws/state` (polls health API every 10s)
- Served on `127.0.0.1:9121` (accessible via Caddy at `cockpit.grid`)

**Design tokens** (adapted from faigate, Grid-tuned):
```css
--bg:          #07101d;   /* deep navy — same as Gate */
--bg-2:        #0d1730;
--panel:       #0d1830cc;
--brand:       #1a7f37;   /* Grid green — distinct from Gate blue */
--brand-2:     #4caf73;
--accent:      #54ABEE;   /* shared fusionAIze blue */
--lime:        #C4D900;
--green:       #2EA75D;
--orange:      #FFAA19;
--danger:      #ff7b7b;
```

Gate uses `--brand:#0052CC` (blue). Grid uses `--brand:#1a7f37` (green) to be visually distinct within the same design language family.

**Navigation rail** (280px sticky left, same layout as faigate):
- fusionAIze Grid wordmark + version badge
- Overview · Nodes · Services · Messenger · Workbench · Signals · Setup
- Bottom: Grid Doctor quick-run button

---

## What this plan defers

| Feature | Reason |
|---|---|
| Multi-instance / fleet view | Signal's job once Grid emits events |
| Cost / token analytics | Gate + Signal's job |
| Advanced anomaly detection | Signal's machine-learning layer (Phase 3) |
| Role-aware dashboard views | Requires fusionAIzeOS integration (Phase 4) |
| Full control plane (start/stop services from UI) | v2.x — safety boundary |
| Enterprise RBAC | Out of Grid's scope entirely |

---

## Success criteria

**Signal Readiness (v1.7–1.9) is done when:**
- `GET /api/v1/health` returns structured node + service state
- `/var/log/faigrid/grid-events.jsonl` is populated by watchdog
- faisignal can be configured to ingest Grid events with zero custom code
- `grid-doctor.sh --json` works

**Cockpit (v2.0) is done when:**
- A new operator can answer in < 2 minutes:
  1. Are all my nodes reachable?
  2. Which services are degraded right now?
  3. What decisions are pending in grid-messenger?
  4. What did my Grid do in the last hour?
- The cockpit runs on `cockpit.grid` in the internal LAN
- No npm, no external CDN, no build step required
