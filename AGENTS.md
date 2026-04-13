# AGENTS.md — fusionAIze Grid

## Project identity & Philosophy

This repository is `faigrid`, the official realization of **fusionAIze Grid**.

**fusionAIze Grid is the sovereign execution substrate for AI-native operations.**
Its job is to define **where** AI-native workloads execute, under **what constraints**, with **what isolation**, through which **queues/runners**, and with which **secrets, observability, and backup patterns**.

It physically provisions and structurally connects the 4+1 Node Architecture:
1. **grid-edge**: Edge ingress workloads (Public intake, TLS, Caddy reverse proxy, Pi-hole DNS, SSO).
2. **grid-core**: Trusted internal services and queued automations (n8n, openclaw, codenomad, faigate, grid-messenger).
3. **grid-worker**: Specialized runners, local model workers (LAN-only inference), and isolated task workers.
4. **grid-backup**: Recovery and observability layer (Restic, Synology).
5. **grid-external**: Cloud model bridges and distributed extensions.

Grid feeds structured runtime health signals (runner failures, service state, queue backlog) into **fusionAIze Signal** (`faisignal`) for cross-layer operational intelligence. Grid's cockpit surface and Signal's ingestion pipeline are designed to be complementary, not overlapping.

In the fusionAIze ecosystem, Grid runs the compute topology. It is explicitly **decoupled** from `fusionAIzeOS`, which serves as the "team operating logic" (defining *how* humans and virtual AI coworkers collaborate, roles, and identity).

**Key Tenets:**
- **Execution First**: Grid operates via strict Execution Classes, not fuzzy environments.
- **Portability**: Explicit Deployment Profiles scale gracefully from the Solo Operator -> Small Team -> SMB.
- **Macher/Builder Focus**: Bash validation, lightweight execution, predictable defaults, 0% enterprise compliance theater.
- **Open Stack**: Standardized on Docker, SSH, POSIX Bash, and open-source models/providers.

## Product priority

The priority is maintaining a universal, highly secure, and easily deployable execution substrate.

Do not optimize the repository around complex web frameworks, operating logic dashboards, or model routing logic (which belong in OS, Gate, and Lens).
Optimize it around rock-solid shell orchestration (`install.sh`), state detection (`~/.config/faigrid/registry/`), cleanly isolated Workbench plugin registries (`plugins/`), runner layer definition (`docker compose`), and robust Bash-level testing (`tests/`).

The Grid Cockpit (planned v2.0) is an exception to the "no web framework" rule — it is a lightweight, no-build, single-file HTML dashboard served by the existing Python messenger process. It stays inside Grid's scope: node health, service status, pending decisions, workbench state. It does not replicate Gate analytics or Signal correlation.

## Architecture principles

Follow these core principles for all additions:
- **Least privilege**: isolate ingress (edge) from internal orchestration (core) from privileged execution (runners).
- **Deny-by-default**: only the edge is exposed; core stays private network only.
- **Secrets never in Git**: rely on `.env.topology` and scoped dynamic runtime keys.
- **Roles, not Hardware**: the ecosystem is built on abstract execution classes that can run anywhere.

## Technical stack

Prefer:
- `bash` (strict mode: `set -euo pipefail`)
- Docker / Docker Compose
- systemd / cron for watchdogs
- Shellcheck for linting (respect `.shellcheckrc`)
- Bats-core for testing (`tests/`)
- GitHub Actions (`release-please` for versioning)

## Code quality rules

- always use absolute paths or securely resolved relative paths (`cd "$(dirname "$0")"`)
- output colorful, readable logs (use `_lib.sh` helpers where possible)
- modular bash scripts over monolithic files
- handle errors gracefully with explicit messages
- **Bash 3.2 compatibility is mandatory** — all scripts must run on macOS (Bash 3.2) and Linux (any distro).
  Forbidden Bash 4+ features:
  - `declare -A` / `declare -gA` — associative arrays → use individual variables or `case` statements
  - `declare -g` — global declaration inside functions → declare at script scope instead
  - `mapfile` / `readarray` → use `while read` loops
  - `${!varname}` indirect expansion with `set -u` — use `case` statements or `eval` carefully
  - `local -A` — local associative arrays → not available

## Workflow rules

Work in small coherent steps.
Prefer commit-sized implementation blocks.
After each major implementation block:
- stop
- summarize what was created
- list open issues or TODOs

Follow the repository branch workflow (if applicable):
- `main` is the protected production branch.
- Feature branches for implementations.
- All commits must follow **Conventional Commits** (e.g., `feat:`, `fix:`, `chore:`) to trigger the `release-please` automated Semantic Versioning bot.

## RTK shell command preference

This infrastructure utilizes `rtk` (Router Toolkit) and `foundrygate`/`faigate` for model routing and token optimization. 
For Codex and other shell-driven agents without native pre-tool hooks, prefer RTK-wrapped shell commands where applicable, to ensure all background AI commands are properly routed and tracked.

Use these mappings by default when interacting with the shell:
- `ls/tree` -> `rtk ls`
- `cat` -> `rtk read`
- `find` -> `rtk find`
- `grep/rg` -> `rtk grep`
- `diff` -> `rtk diff`
- `git` -> `rtk git`
- `gh` -> `rtk gh`

Use raw commands only when RTK is not a good fit, or when explicitly testing raw OS behavior.

## Documentation rules

Maintain:
- `README.md` and `ROADMAP.md` aligned with `fusionAIze Grid` ("sovereign execution substrate") nomenclature.
- Core Runbooks in `docs/runbooks/`
- Workbench plugin definitions

## Security rules

- Never hardcode IP addresses or secrets.
- Always prompt the user for target IPs or derive them from `.env.topology`.
- Explicitly support backup and observability by default.
