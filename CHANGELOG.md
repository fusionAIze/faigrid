# Changelog

All notable changes to fusionAIze Grid are documented in this file.
Generated from conventional commits using [git-cliff](https://git-cliff.org).

## [1.6.0] — 2026-04-02

### Features
- (`workbench`) Add Caddy reverse proxy plugin for internal LAN `.grid` TLD setup with Pi-hole DNS integration
- (`workbench`) Add grid-messenger Telegram bridge with multi-type decision framework (approve/choice/input)
- (`workbench`) Add app source registry and Telegram topic thread routing to grid-messenger
- (`workbench`) Add openclaw self-update fallback via GitHub release download
- (`workbench`) Add Projects manager and Skills manager with cross-agent translator
- (`workbench`) Add Doctor menu for installed tool diagnostics

### Bug Fixes
- Move `LOCAL_REGISTRY` and `TOPOLOGY_FILE` to user-scoped `~/.config/faigrid/` paths — fixes Homebrew install not finding registered nodes
- (`core`) Auto-generate n8n encryption key and Postgres password on install
- (`core`) Add n8n startup grace period detection to verify.sh
- (`workbench`) Fix multi-select install, n8n stopped state, navigation

### CI/CD
- Add `.pre-commit-config.yaml` with ShellCheck, conventional commits, file hygiene hooks
- Add `.cliff.toml` for automated changelog generation
- Add `codeql.yml` CodeQL security scanning
- Add `release-please.yml` automated release workflow with Homebrew tap notification
- Add version consistency check to `lint.yml`
- Add Python ruff linting for `core/messenger/src/`
- Add `.devcontainer/` for consistent development environment
- Add `scripts/faigrid-release` release preparation helper

### Miscellaneous
- Add `VERSION` file as single source of truth for version tracking
- Migrate Homebrew formula to `fusionAIze/homebrew-tap`

## [1.5.1] — 2025 (previous)

Initial public release with core orchestrator, edge/core/worker node setup,
workbench plugin system, and openclaw/n8n/faigate integration.
