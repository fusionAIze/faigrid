# Fusionaize organization SkillWeave helper

Durable planning for every repository in the Forgejo `fusionaize` organization is centralized in the
private `fusionaize/fusionaize-planning` repository.

- Canonical: `https://git.langevc.com/fusionaize/fusionaize-planning`
- Local clone: `/Users/andrelange/Documents/repositories/forgejo/fusionaize/fusionaize-planning`
- Board: `.skillweave/planning/BOARD.md` · Playbook: `PLAYBOOK.md` · Schema: `TICKET-SCHEMA.md`

## When SkillWeave starts in this repository
1. Read this repo's root instructions; inspect branch, worktree, tests, linked Forgejo issue/PR.
2. Read the central board + playbook. Reuse the existing central ticket; create one only if none exists.
3. Do not create a durable repo-local `.skillweave/planning` tree — local SkillWeave is ephemeral + ignored.
4. Keep planning fields/status/deps/acceptance/evidence/handoffs in the central ticket; discussion in Forgejo.
5. Before handoff: record ticket ID, repo/branch, commits/PRs, tests, remaining, blockers, next gate.
6. Let `fusionaize-ops` mirror Forgejo comments/state. Bot markers + sync-state are machine-managed.

If planning/sync is unavailable, do not fork the backlog — keep a temporary local note, avoid destructive
cleanup, reconcile when service returns.
