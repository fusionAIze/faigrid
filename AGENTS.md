# AGENTS.md — fusionAIze Nexus Labs

## Project identity

This repository is `fusionaize-nexus-labs`, a modular reference stack for running a secure, self-hosted **agent + automation** environment.

Its purpose is to provide a standardized, generic 4+1 Node Architecture:
1. **nexus-edge**: Ingress, TLS, reverse proxy, optional DNS/SSO.
2. **nexus-core**: The orchestrator and AI Workbench (n8n, OpenClaw, routing, plugins).
3. **nexus-worker**: Local LLM execution backend (e.g., LM Studio, Ollama).
4. **nexus-backup**: Backup targets.
5. **nexus-external**: Public cloud extensions.

## Product priority

The priority is maintaining a universal, highly secure, and easily deployable bash-driven infrastructure.

Do not optimize the repository around complex web frameworks.
Optimize it around rock-solid shell orchestration (`install.sh`), state detection (`.nexus-state`), and clean plugin registries for the Workbench.

## Architecture principles

Follow these core principles for all additions:
- **Least privilege**: isolate ingress, orchestration, and execution.
- **Deny-by-default**: only the edge is exposed; core stays private.
- **Secrets never in Git**: rely on `.env.topology` and `.env` templates.
- **Roles, not Hardware**: the ecosystem is built on abstract roles that can run anywhere.

## Technical stack

Prefer:
- `bash` (strict mode: `set -euo pipefail`)
- Docker / Docker Compose
- systemd / cron for watchdogs
- Shellcheck for linting (respect `.shellcheckrc`)
- GitHub Actions (`release-please` for versioning)

## Code quality rules

- always use absolute paths or securely resolved relative paths (`cd "$(dirname "$0")"`)
- output colorful, readable logs (use `_lib.sh` helpers where possible)
- modular bash scripts over monolithic files
- handle errors gracefully with explicit messages

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

This infrastructure utilizes `rtk` (Router Toolkit) and `FoundryGate` for model routing and token optimization. 
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
- `docs/architecture.md`
- `docs/ROADMAP.md`
- Core Runbooks in `docs/runbooks/`
- Workbench plugin definitions

## Security rules

- Never hardcode IP addresses or secrets.
- Always prompt the user for target IPs or derive them from `.env.topology`.
- Use explicit double-check warnings before destructive actions (like overwriting existing installations).
