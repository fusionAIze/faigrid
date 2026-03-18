# CLAUDE.md — fusionAIze Nexus Labs

**Read `AGENTS.md` first.** It contains the foundational architecture context (4+1 Node Setup) and universal rules for this repository.

## Quick Context for Claude Code

- **Domain**: Shell-driven AI Infrastructure Orchestration.
- **Language**: Strict Bash (`set -euo pipefail`).
- **Core Engine**: `install.sh` orchestrator with `.nexus-state` detection.
- **Default AI Role**: Claude is often utilized for deep architectural reviews, structural bash rewrites, and security hardening patches.

## Project Instruction Summary

When working in this repository, prioritize **security, simplicity, and cross-OS compatibility** (macOS vs Linux).

Claude should mainly:
- remove bugs and handle shell edge cases
- reduce unnecessary risks (e.g., command injection vulnerabilities in `install.sh`)
- make light structural improvements
- improve modularity in Workbench plugins

Apply these code quality rules:
- rely on `ShellCheck` rules. If an exception is needed, update `.shellcheckrc` or use an inline disable comment.
- always use safety checks before moving/deleting data. If writing to a file, verify the directory exists.

Work in small coherent steps and prefer commit-sized implementation blocks. 

## Key Deliverables

- `install.sh` (Root Orchestrator)
- `core/workbench/scripts/` (Plugin Registry)
- `docs/ROADMAP.md` (Versioning Base: v0.0.1)

## Commit Messages & Versioning

We use `release-please`. Your commit messages **must** follow conventional commits (`feat:`, `fix:`, `docs:`, `chore:`) to ensure correct automated version bumps (Patch/Minor until v1.0.0).

## RTK Shell Commands

This environment heavily promotes `rtk` (Router Toolkit) for model interoperability.
Whenever possible, run wrapped commands:

```bash
rtk ls            # instead of ls/tree
rtk read          # instead of cat
rtk grep          # instead of grep/rg
rtk find          # instead of find
rtk git           # instead of git
```

Use raw OS commands only when `rtk` lacks the necessary flags or when running native infrastructure actions (like `systemctl`, `apt`, `brew`).
