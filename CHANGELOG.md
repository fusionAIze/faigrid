# Changelog

All notable changes to fusionAIze Grid are documented in this file.
Generated from conventional commits using [git-cliff](https://git-cliff.org).

## [1.6.1](https://github.com/fusionAIze/faigrid/compare/v1.6.0...v1.6.1) (2026-04-02)


### Bug Fixes

* **ci:** resolve ruff lint failures and add pre-push validation ([ecadc78](https://github.com/fusionAIze/faigrid/commit/ecadc78c1061f86814c8b1ecf00276440ce54ceb))
* **ci:** ruff format + smarter CHANGE_ME smoke test ([56e170c](https://github.com/fusionAIze/faigrid/commit/56e170c3d1ad56295ae0d6738285833dbdb5c5f1))


### CI/CD

* re-trigger release-please after permissions fix ([5c657e6](https://github.com/fusionAIze/faigrid/commit/5c657e60cd7c9972b6d87b041dcd3e2de5bb9dbd))


### Miscellaneous

* complete benchmark template alignment ([73e21d4](https://github.com/fusionAIze/faigrid/commit/73e21d444ee92b162ad112d35cf1ef4182738111))

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
