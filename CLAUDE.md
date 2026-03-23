# CLAUDE.md — fusionAIze Grid

**Read `AGENTS.md` first.** It contains the foundational architecture context (4+1 Node Setup) and universal rules for this repository.

## Quick Context for Claude Code

- **Domain**: Shell-driven AI Infrastructure Orchestration.
- **Language**: Strict Bash (`set -euo pipefail`).
- **Core Engine**: `install.sh` orchestrator with `.grid-state` detection.
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

## Operational Guardrails

1. **Deny-by-default**: Never expose ports beyond `localhost` or internal subnets unless they are explicitly destined for `grid-edge` ingress. All core services bind to `127.0.0.1`.
2. **State Detection First**: The main `install.sh` parses `~/.grid-state`. Always check existing state before provisioning to avoid unintended overwrites.
3. **No destructive scripts without safeguard**: Any script that purges volumes, removes stack directories, or drops databases must include an explicit user confirmation prompt before executing.
4. **Bash 3.2 compatibility is mandatory** — macOS ships Bash 3.2; all scripts must run on it.
   Forbidden Bash 4+ features:
   - `declare -A` / `declare -gA` — associative arrays → use individual variables or `case` statements
   - `declare -g` — global declaration inside functions → declare at script scope instead
   - `mapfile` / `readarray` → use `while read` loops
   - `${!varname}` indirect expansion under `set -u` → use `case` statements

## Security Guidelines

- **Never hardcode IP addresses or secrets.** Derive targets from `.env.topology`; derive credentials from `.env` templates.
- **Secrets never in Git.** Token files, `.env`, and credentials live outside the repo. `.gitignore` must cover them.
- **Prompt before destructive actions.** Uninstall, wipe, or volume removal must warn the user and require confirmation.

### System User & Service Isolation Pattern

When writing install scripts that register persistent services (systemd units), follow the openclaw pattern — never run services as root:

```bash
# 1. Create dedicated system user (no login shell, no home dir)
sudo useradd -r -s /usr/sbin/nologin -M <service>

# 2. Own config/secret files as root:<service>, mode 640
sudo chown root:<service> /etc/<service>/secret.token
sudo chmod 640            /etc/<service>/secret.token

# 3. Restrict config directory itself
sudo chown root:<service> /etc/<service>/
sudo chmod 750            /etc/<service>/

# 4. Reference in systemd unit
# [Service]
# User=<service>
# Group=<service>
```

Apply this pattern consistently:
- Dedicated user per service (e.g., `openclaw`, `grid`)
- All secret files: `root:<service>` / `640`
- Service directories: `root:<service>` / `750`
- Runtime data dirs owned by the service user: `<service>:<service>` / `750`
