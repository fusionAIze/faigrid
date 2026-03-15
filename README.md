# fusionAIze Nexus Labs

[![Lint](https://github.com/typelicious/fusionaize-nexus-labs/actions/workflows/lint.yml/badge.svg)](https://github.com/typelicious/fusionaize-nexus-labs/actions/workflows/lint.yml)
[![Test](https://github.com/typelicious/fusionaize-nexus-labs/actions/workflows/test.yml/badge.svg)](https://github.com/typelicious/fusionaize-nexus-labs/actions/workflows/test.yml)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Bash](https://img.shields.io/badge/Language-Bash-4EAA25.svg)](https://www.gnu.org/software/bash/)
Open-source, modular reference stack for a **secure agent + automation** setup.

**Core idea:** Edge (secure ingress) → Core (n8n + OpenClaw) → Workers (LLM/runner) → Backups/Observability.

## Start here

- [Step 01 — Pi Edge (Headless)](docs/runbooks/step-01-pi-edge.md)

> Security note: This repository is a template. **Never commit secrets**. Use `.env.example` files only.

## Table of Contents
- [Modules (high-level)](#modules-high-level)
- [Repository layout](#repository-layout)
- [License](#license)

## Modules (high-level)

- **nexus-edge**: secure ingress + DNS (Pi-hole), reverse proxy (Caddy), optional SSO/2FA + abuse protection (runs on Raspberry Pi)
- **nexus-core**: AI Hub / Workbench with internal n8n + OpenClaw + Routing (FoundryGate, RTK) + CLI agents (kilo, codex, etc.) (runs on Mini-PC)
- **nexus-worker**: local LAN LLM serving for isolated, cost-optimized coding/review tasks (runs on older MacBook)
- **nexus-backup**: offline backups and restore target (runs on Synology NAS)
- **nexus-external** *(optional)*: Public cloud extension (e.g. Hetzner) running Agency-PM (Plane) + External n8n communicating with internal core

## Repository layout

- `core/` — docker compose stacks, systemd servers, and core orchestration logic
- `docs/` — runbooks, architecture, extensions
- `edge/pi/` — scripts + configs for the Pi (nexus-edge)
- `scripts/` — global scaffolding and repository utilities

## License

Apache 2.0 — see [LICENSE](LICENSE).
