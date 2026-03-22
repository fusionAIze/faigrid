# Contributing to fusionAIze Grid

Thank you for your interest in contributing to the Nexus architecture!

This repository serves as a generic standard for a 4+1 Node AI infrastructure. When contributing, please ensure your architectural additions align with the design principles:

1. **Deny-by-default**: Only `grid-edge` should be exposed.
2. **Secrets never in Git**: Rely on `.env` templates.
3. **Roles, not Hardware**: The ecosystem is built on abstract roles that can be adapted anywhere.

## Adding a new Tool to the Workbench

The most common contribution is adding a new CLI, Agent, or Router to the **Workbench Control Center** on `grid-core`.

To do this, you do not need to edit the core application code. Instead, use the Plugin System:

1. Copy the template from `core/workbench/scripts/plugins/_template.sh`.
2. Name it according to your tool (e.g., `my-agent.sh`).
3. Place it in the appropriate category under `core/workbench/scripts/plugins/`:
   - `clis/`
   - `routers/`
   - `memory/`
   - `agents/`
   - `automation/`
   - `wrappers/`
4. Fill out the `tool_install`, `tool_update`, and `tool_status` functions inside your plugin.
5. Create a Pull Request! The CI pipeline will automatically run ShellCheck on your plugin.

## Submitting Pull Requests

- **Linting**: Ensure your Bash scripts pass Shellcheck without errors. CI will enforce this.
- **Testing**: Whenever possible, run `bash -n <script>` locally before committing.

## Commit Messages & Releases

This repository uses [Release Please](https://github.com/googleapis/release-please) to automatically generate changelogs and version bumps. 
**Important Baseline**: `v0.0.1` is our foundational release. All work builds upon this. Until `v1.0.0`, features and fixes will strictly increment the minor/patch versions. 

Therefore, **all commit messages and PR titles must follow [Conventional Commits](https://www.conventionalcommits.org/) format.**

Examples:
- `feat: add deepseek cli plugin to workbench` (Creates a feature bump, e.g. `v0.1.0` or `v0.0.2` depending on pre-1.0 rules in the next release)
- `fix: correct typo in openclaw restart script` (Creates a bugfix patch bump, e.g. `v0.0.3` in the next release)
- `docs: update architecture documentation` (Does not trigger a new release, just updates the repo)
- `chore: update github action runners` (Does not trigger a new release)
