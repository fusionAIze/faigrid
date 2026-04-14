# Grid Operator Cockpit — Design Specification

## Purpose

The Grid Cockpit is a **lightweight, operator-focused web dashboard** for fusionAIze Grid. It answers the same class of question for Grid that the faigate operator cockpit answers for Gate — but scoped entirely to Grid's execution substrate: node health, service status, pending decisions, and runtime events.

It is not a control plane. It does not replicate Gate's routing analytics or Signal's cross-layer correlation. Its scope is: **what is happening in my Grid right now, and is everything OK?**

---

## Context

### What the faigate cockpit teaches us

faigate's operator cockpit (`dashboard_web.py`, `DASHBOARD-IA.md`) established a design language and IA pattern for the fusionAIze stack:

- **Dark navy theme** — `--bg:#07101d`, deep blue palette
- **280px sticky left rail** — brand lockup, navigation, version indicator
- **Card-based panels** — grouped by operator job, not by data type
- **Jobs first, metrics second** — every section answers one question
- **No-build, inline HTML** — served directly from Python/aiohttp, zero npm
- **Progressive disclosure** — overview compact, detail on drilldown

The Grid Cockpit follows this design language family but uses **Grid green** (`#1a7f37`) as the brand color to be visually distinct from Gate blue (`#0052CC`).

### What faisignal expects from Grid

From the faisignal roadmap, Signal v1 expects to ingest from Grid:
- runner failure events
- queue backlog anomalies
- job-completion degradation
- local/cloud worker imbalance

The cockpit is the **human-facing surface** of the same runtime state that Signal ingests programmatically. They read the same data; they serve different audiences.

---

## Design Principles

1. **Jobs first** — each cockpit section answers exactly one operator job.
2. **Confidence before detail** — Overview gives a pass/fail grid health signal in one glance.
3. **Read-only first** — cockpit observes; it does not mutate state. Actions stay in Workbench CLI.
4. **Signal-compatible** — cockpit sections map to faisignal's runtime health signal family.
5. **Lightweight** — no CDN, no npm, no build. Single Python file + inline HTML.
6. **Distinct but consistent** — uses faigate's design language; Grid green differentiates it.

---

## Visual Design

### Color tokens

```css
:root {
  /* Base — shared with faigate */
  --bg:           #07101d;
  --bg-2:         #0d1730;
  --panel:        #0d1830cc;
  --panel-strong: #101d38;
  --panel-soft:   #12224480;
  --line:         #1e3a2a;
  --line-soft:    #172e22;
  --text:         #dbe6f5;
  --muted:        #8ea7cc;
  --muted-soft:   #6980a6;

  /* Grid brand — green (Gate = blue #0052CC) */
  --brand:        #1a7f37;
  --brand-2:      #4caf73;
  --brand-glow:   rgba(26, 127, 55, 0.12);

  /* Shared fusionAIze accent */
  --accent:       #54ABEE;

  /* State colors — same as Gate */
  --lime:         #C4D900;
  --green:        #2EA75D;
  --orange:       #FFAA19;
  --danger:       #ff7b7b;

  /* Layout */
  --radius-xl:    28px;
  --radius-lg:    20px;
  --radius-md:    14px;
  --radius-sm:    10px;
  --shadow:       0 20px 56px rgba(2, 8, 19, .28);

  /* Typography */
  --body:         "Open Sans", "Segoe UI", "Helvetica Neue", sans-serif;
  --display:      "Montserrat", "Avenir Next", "Segoe UI", sans-serif;
  --mono:         "SFMono-Regular", "IBM Plex Mono", "Menlo", monospace;
}
```

### Layout

```
┌───────────────────────────────────────────────────────────────────────┐
│                                                                       │
│  ┌────────────────┐  ┌──────────────────────────────────────────────┐ │
│  │  LEFT RAIL     │  │  MAIN CONTENT                                │ │
│  │  280px sticky  │  │  fluid width                                 │ │
│  │                │  │                                              │ │
│  │  [Grid logo]   │  │  [Section header]                           │ │
│  │  [wordmark]    │  │                                              │ │
│  │  [version]     │  │  [Cards / panels / tables]                  │ │
│  │                │  │                                              │ │
│  │  ─────────     │  │                                              │ │
│  │  Overview      │  │                                              │ │
│  │  Nodes         │  │                                              │ │
│  │  Services      │  │                                              │ │
│  │  Messenger     │  │                                              │ │
│  │  Workbench     │  │                                              │ │
│  │  Signals       │  │                                              │ │
│  │  Setup         │  │                                              │ │
│  │                │  │                                              │ │
│  │  ─────────     │  │                                              │ │
│  │  [Doctor btn]  │  │                                              │ │
│  └────────────────┘  └──────────────────────────────────────────────┘ │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

CSS grid: `grid-template-columns: 280px minmax(0, 1fr)` — same as faigate.

### Status indicators

| State | Color | Usage |
|---|---|---|
| healthy / ok | `--green` #2EA75D | Service up, node reachable |
| degraded | `--orange` #FFAA19 | Partial failure, stale data |
| down / error | `--danger` #ff7b7b | Service down, node unreachable |
| unknown | `--muted` #8ea7cc | No data yet |
| pending | `--lime` #C4D900 | Decision awaiting response |

---

## Information Architecture

### 1. Overview

**Operator job**: "Is my Grid healthy and ready right now?"

**Layout**: 2×3 summary card grid + priority-next banner

**Content:**
- **Node status row** — 5 badges (edge / core / worker / backup / external), each showing reachable / unreachable / unknown
- **Service health** — count of healthy / degraded / unknown services across all nodes
- **Pending decisions** — count of open decisions in grid-messenger + type breakdown (approve / choice / input)
- **Last event** — timestamp + one-line summary of most recent entry in grid-events.jsonl
- **Grid version** — installed version from `VERSION` file
- **Priority next** — top anomaly detected (e.g., "worker node unreachable since 14:32")

**Why this order:**
Node health first (infrastructure confidence), then service health (application confidence), then decisions (operational backlog), then last event (recent activity).

---

### 2. Nodes

**Operator job**: "Which nodes are reachable and what are they running?"

**Layout**: One card per node (5 cards), horizontal or 2-column grid

**Per-node card:**
- Node name + role badge (`edge` / `core` / `worker` / `backup` / `external`)
- Reachability status + last-seen timestamp
- Services list with inline status icon
- SSH target label (hostname or IP class only — not full credentials)
- Link to detail view

**Node detail panel (slide-in or expandable):**
- Full service list with port, status, last-checked
- Recent events for this node (filtered from event log)
- Link to Workbench plugin for each service

---

### 3. Services

**Operator job**: "Which services are up, degraded, or stale?"

**Layout**: Filterable table + detail panel

**Table columns:** Service · Node · Port · Status · Last checked · Action

**Filters:** All / Healthy / Degraded / Down / Unknown

**Detail panel per service:**
- HTTP health probe response (if applicable)
- Recent log lines (last 10 lines from journalctl / service log)
- Workbench plugin link for reconfiguration
- Uptime since last restart

---

### 4. Messenger

**Operator job**: "What decisions are pending? What did my apps send recently?"

**Layout**: Two-column — pending (left) + history (right)

**Pending decisions:**
- Card per pending decision: type badge · source emoji + name · description · time-in-queue
- Sorted by age (oldest first — most urgent)
- Cancel button (POST to messenger API)

**Decision history (last 20):**
- Compact list: type · source · choice/approval · resolved-by · timestamp
- Click to expand full payload

**Registered apps:**
- Compact list with emoji, display name, last-active, thread_id if set

**Telegram link:**
- Direct link to open bot conversation (t.me/...)

---

### 5. Workbench

**Operator job**: "Which plugins are installed, configured, and healthy?"

**Layout**: Plugin cards in 2×N grid

**Per-plugin card:**
- Plugin name + category badge
- Installation status (installed / not installed)
- Configuration status (configured / unconfigured)
- Health status (last doctor run result)
- Update available indicator
- Quick-actions: Configure · Doctor · Update (link to Workbench CLI command)

---

### 6. Signals

**Operator job**: "What events has my Grid emitted recently?"

**Layout**: Event timeline + filter bar

**Timeline entry:**
- Timestamp · Event type badge · Node · Service · Detail text

**Event types (with color coding):**
| Type | Color |
|---|---|
| `service_down` | `--danger` |
| `service_recovered` | `--green` |
| `node_unreachable` | `--danger` |
| `node_recovered` | `--green` |
| `decision_requested` | `--lime` |
| `decision_resolved` | `--accent` |
| `plugin_installed` | `--brand-2` |
| `plugin_updated` | `--brand-2` |

**Filter bar:** All · Service · Node · Decision · Plugin · Time range

**Live mode toggle:** WebSocket tail of grid-events.jsonl (auto-refreshes on new events)

**faisignal integration note:** Compact link "View in Signal →" if faisignal is detected at its default port.

---

### 7. Setup

**Operator job**: "How do I register a new node or configure a missing service?"

**Layout**: Step-by-step wizard panels

**Sections:**
- Node registration (topology flags, registry path)
- Workbench plugin quick-start (per-plugin install command)
- Messenger setup (bot token, chat ID, app registration)
- Caddy / Pi-hole DNS setup
- Link to `grid-doctor.sh` and `docs/runbooks/`

---

## Navigation Rail — Detail

```
┌─────────────────────────────┐
│  [fusionAIze wordmark SVG]  │
│  Grid  v1.7.0               │  ← version badge, brand-green
│                             │
│  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄   │
│                             │
│  ⬡  Overview                │  ← active state: brand-green left border
│  ◉  Nodes                   │
│  ◈  Services                │
│  ✉  Messenger               │  ← badge: pending decision count
│  ⚙  Workbench               │  ← badge: updates available count
│  ⚡  Signals                 │
│  ✦  Setup                   │
│                             │
│  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄   │
│                             │
│  [Run Doctor]               │  ← pill button, opens Signals section
│                             │
└─────────────────────────────┘
```

---

## Technical Specification

### File layout

```
core/cockpit/
├── grid_cockpit.py           # aiohttp app + API endpoints + WebSocket
├── dashboard_web.py          # Inline HTML/CSS/JS (single-file, no build)
├── assets/
│   └── brand/
│       ├── grid-wordmark.svg
│       └── favicon.ico
├── install.sh                # Creates system user, installs service
└── systemd/
    └── grid-cockpit.service
```

### HTTP API (served by grid_cockpit.py)

```
GET  /                        → dashboard HTML
GET  /dashboard/assets/*      → static assets
GET  /api/v1/health           → node + service health JSON
GET  /api/v1/events           → last N events from grid-events.jsonl
GET  /api/v1/messenger        → pending decisions + registered apps
GET  /health                  → cockpit self-health
WS   /ws/state                → live push: health diffs + new events
```

### System service

- Port: `127.0.0.1:9121`
- User: `grid-cockpit` (no login shell, no home dir)
- Config: `/etc/grid-cockpit/config.env`
- Accessible via Caddy at: `cockpit.grid` (internal LAN, `.grid` TLD)
- Reads: `~/.config/faigrid/registry/*.state`, `/var/log/faigrid/grid-events.jsonl`
- Proxies to: `127.0.0.1:9119` (grid-messenger health/decisions)

### Workbench plugin

```
core/workbench/scripts/plugins/ops/grid-cockpit.sh
```

Standard interface:
- `tool_configure()` — set port, messenger URL, event log path
- `tool_doctor()` — check service running, HTTP health, Caddy route active
- `tool_update()` — pull latest from source

---

## Scope Boundary

| In scope | Out of scope |
|---|---|
| Node reachability (Grid's own nodes) | Faigate provider health |
| Grid service status (n8n, openclaw, etc.) | Signal cross-layer correlation |
| Pending decisions (grid-messenger) | Token usage / cost analytics |
| Grid event timeline | LLM inference quality metrics |
| Workbench plugin status | Route selection explainability |
| Grid setup / onboarding | RBAC / multi-user governance |

The cockpit is intentionally narrow. Cross-layer intelligence belongs to Signal; routing intelligence belongs to Gate.

---

## Licensing

Grid Cockpit ships under **Apache 2.0** — same as faigrid.

The read-only local dashboard (node health, service status, messenger decisions, event log) is a core operator tool and must stay open.
