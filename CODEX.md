# CODEX.md — fusionAIze Grid

**Read `AGENTS.md` first.** It contains the foundational architecture context (4+1 Node Setup) and universal rules for this repository.

## Quick Context for Codex CLI

- **Domain**: Shell-driven AI Infrastructure Orchestration.
- **Language**: Strict Bash (`set -euo pipefail`).
- **Core Engine**: `install.sh` orchestrator with `.grid-state` detection.
- **Default AI Role**: Codex is meant to be a rapid terminal executor, operating heavily on shell pipelines and local system automation tasks.

## Project Instruction Summary

When acting in this environment, Codex should prioritize **shell-safe execution and idempotent scripts**.

- Only create directories (`mkdir -p`) if checking their existence first.
- Only run destructive commands (`rm -rf`) if explicitly guarded by a user confirmation prompt.
- Always output readable, colored logs using the standardized Helpers (e.g., `info()`, `warning()`, `success()`).

## RTK Shell Commands

Since Codex is a shell-driven tool without inherent sandboxing, it relies on `rtk` (Router Toolkit) mappings for execution.

Always execute:
```bash
rtk ls            # instead of ls/tree
rtk read          # instead of cat
rtk grep          # instead of grep/rg
rtk find          # instead of find
rtk git           # instead of git
```

Do not execute raw file explorations (`cat /etc/passwd`) unless wrapped in `rtk read`, ensuring token optimization and safety routing.
