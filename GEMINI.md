# GEMINI.md — fusionAIze Nexus Labs

**Read `AGENTS.md` first.** It contains the foundational architecture context (4+1 Node Setup) and universal rules for this repository.

## Quick Context for Gemini CLI

- **Domain**: Shell-driven AI Infrastructure Orchestration.
- **Language**: Strict Bash (`set -euo pipefail`).
- **Core Engine**: `install.sh` orchestrator with `.nexus-state` detection.
- **Default AI Role**: Rapid pipeline prototyping, integration modeling, and analytical documentation structure.

## Project Instruction Summary

For Gemini, prioritize **speed and functionality** when generating configurations, composing Docker networks, or implementing fast plugin templates for the `nexus-core` Workbench.

**Gemini's specific focus:**
- Implement and refine logic in `core/heart/compose/` (Docker networking context).
- Ensure explicit and safe environment variables exist in `.env` templates.
- When generating Markdown documentation, utilize clear GitHub-flavored alerts (`> [!WARNING]`).

## Operational Guardrails

1. **Deny-by-default**: Ensure ports are only exposed to `localhost` or specific internal subnets unless they are explicitly meant for `nexus-edge` ingress.
2. **State Detection First**: Acknowledge that the main `install.sh` parses `~/.nexus-state`. 
3. **No destructive scripts without warning**: If you write a bash script that purges volumes, you must include an explicit user prompt.
4. **Bash 3.2 compatibility is mandatory** — macOS ships Bash 3.2; all scripts must run on it.
   Never use: `declare -A`, `declare -gA`, `mapfile`, `readarray`, `local -A`, or `${!var}` indirect expansion under `set -u`.
   Use instead: individual variables, `case` statements, `while read` loops.


## Tool Usage & Shell Commands

As a native tool-driven agent, use your built-in tools (`read_file`, `run_command`, etc.). 

If you spawn shell commands that are routed via the AI node, remember that `rtk` (Router Toolkit) is the preferred wrapper in this ecosystem:
```bash
rtk ls            # list dirs
rtk read          # read files
rtk grep          # exact matching
```

## AI Delivery Protocol

After completing a task, always report:
1. Scripts modified/created.
2. Changes to topology or state detection.
3. Test commands (e.g., `bash -n install.sh`).
4. Recommended next steps based on `docs/ROADMAP.md`.
