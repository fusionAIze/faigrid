# Changelog

All notable changes to fusionAIze Grid are documented in this file.
Generated from conventional commits using [git-cliff](https://git-cliff.org).

## [1.10.1](https://github.com/fusionAIze/faigrid/compare/v1.10.0...v1.10.1) (2026-09-25)


### Bug Fixes

* **installer:** `install.sh` announced the previous version. Its header comment and the version it prints on start both read 1.9.0 while the release was 1.10.0, so an operator running the installer saw a version that did not match the artifact they had fetched. The repository already carried a test asserting the two agree; it is now green again

## [1.10.0](https://github.com/fusionAIze/faigrid/compare/v1.9.0...v1.10.0) (2026-09-25)


### Features

* **supervisor:** faigrid gains its first HTTP surface. The Supervisor presents the Scheduler, the Runner Pool and the Recovery Engine through a Control API on `faigrid-core:5000` — register a worker, poll status, read a job's recovery history, ask for the worker ceiling. It answers on the control network only; the same request from the inference network is refused, so the first API does not weaken the isolation between the two planes. `recovery_history` reads the journal the recovery engine already writes and preserves its correlation ids rather than keeping a second record of the same events
* **inference gateway:** a gateway can now run as a container on the tenant inference network, where a nested tenant resolves it by name. It publishes no host port and joins exactly one network, so it is reachable from the inference plane and from nowhere else
* **worker, llama.cpp:** `worker/scripts/install.sh` recognises llama.cpp alongside Ollama and LM Studio, names its tunnel port the way it already named the other two, and states the 8GB guidance in llama.cpp's own terms. A worker with none of the three engines present is now told so by engine name instead of completing silently
* **worker, reusable library:** `worker/lib/worker-env.sh` carries the machine-independent half of a worker setup — engine resolution by absolute path, a fail-closed API-key read, a caffeinate-wrapped server command that keeps the key in the environment rather than in the process arguments, an HTTP health check and a liveness helper. Nothing in it names a particular machine
* **worker, health:** `worker/scripts/verify.sh` probes the inference endpoint over HTTP. It previously checked only whether an engine's CLI was installed, which a stopped server passes

### Documentation

* **runbooks:** installing and supervising a worker as a durable service, deploying the gateway on the inference network, delivering tenant images from a registry, and a reference separating what a worker setup contributes generically from what belongs to one machine

### Tests

* the tenant preflight is now proven against a live substrate rather than a local daemon: it succeeds on a ready substrate, and with one tenant network removed it refuses by name and creates nothing, shown by an unchanged container list
* a worker's reachability is asserted from another host — that the endpoint answers without a session holding it open, that the machine is kept awake while the server runs, and that an unreachable worker is named by endpoint instead of failing generically

## [1.9.0](https://github.com/fusionAIze/faigrid/compare/v1.8.0...v1.9.0) (2026-09-24)


### Features

* **tenant substrate:** faigrid can host a nested tenant. Five new modules under `core/tenant/`: isolated control and inference networks, a preflight that refuses a tenant start on an unready substrate, tenant routing with attributable cost, a dual-homed credential mediator with IP forwarding off, and an append-only recovery journal a tenant can poll for gaps
* **tenant networks:** `core/tenant/networks.sh` provisions `faigrid_control_net` and `faigrid_inference_net` as separate bridges, each labelled with its creator. Isolation is verified by a refused cross-network connection, not by reading configuration
* **preflight:** a tenant start is refused by name when either network is absent or unhealthy, before any container is created
* **tenant routing:** a request carrying an organisation and tenant identifier is routed and recorded by value. A request with no tenant identifier is refused or attributed to an explicit default, never silently attributed to nobody
* **credential mediator:** exactly one dual-homed container bridges the two networks with IP forwarding off. Workers obtain scoped tokens through it and cannot reach the broker directly; no long-lived secret is held in a worker environment
* **recovery journal:** a worker restart appends an event preserving the original correlation id, with a readable write position so a consumer can detect a gap from its own cursor. With the notification webhook unreachable the event is still recorded and the job continues


### Bug Fixes

* **install:** `install.sh` completes non-interactively. `--mode local|remote` now sets the execution mode directly; previously passing `--mode` skipped the block that assigned it and the run aborted under `set -u`. The numeric prompt mapping remains for interactive use
* **logging:** `log_event` writes through `sudo` to both log files. The `750 root:adm` permission model granted the `adm` group read access but never write, so every non-root event was discarded silently. Where passwordless sudo for the log path is unavailable, `log_event` now fails by name instead of discarding. The misleading `adm` group membership is removed — the modes never granted write
* **release:** the Forgejo release producer publishes to every destination declared in `.ops.yaml` and gates publication on the release title and the presence of a changelog section for the tag. A refused release no longer reaches the Homebrew tap: the tap notifier keys on the published release object rather than on the tag push


### Documentation

* runbooks for the node install and for reconstructing a compose definition from running containers
* a substrate readiness report stating, per handover clause, met / not met / out of scope


## [1.8.0](https://github.com/fusionAIze/faigrid/compare/v1.7.0...v1.8.0) (2026-08-22)


### Bug Fixes

* **optimization round (O1–O12):** version truth, --setup KeyError, least-privilege logs, .env.topology untracking, _projects precedence, grid-doctor macOS portability, single state registry, eval removal, JSONL logging, executor contract, scoped --force


### Closeout (FAI-207, C1–C11)

* **grid-doctor:** macOS memory reads vm_stat page size; JSONL severity count; read-only (no state writes)
* **logging:** log_event write path reaches disk (adm membership, once-only setup); grid-events.jsonl rotatable; overridable LOG_DIR
* **install:** --yes parity restored (AUTO_YES read), prompt() printf-v; one migration semantic
* **ci:** version check can actually fail (fetch-depth 0, exact-match tag); pytest job on ubuntu+macos; bats --regression/--integration; executor-contract conformance check
* **messenger:** pytest runs against real deps (stubs only on ImportError); /api/v1/health real-routing test
* **skills:** npx dispatch without unquoted expansion


### CI/CD

* **forgejo-first:** unified mirror workflow, CI guards, dev pointers ([#22](https://github.com/fusionAIze/faigrid/issues/22))


## [1.7.0](https://github.com/fusionAIze/faigrid/compare/v1.6.2...v1.7.0) (2026-04-14)


### Features

* **cli:** agent-native CLI surface for faigrid + /api/v1/health ([6487ba9](https://github.com/fusionAIze/faigrid/commit/6487ba905dad1fcf6885daffe97a338a0235168a))
* **messenger:** add fgm CLI + setup wizard + decision polling ([cea991e](https://github.com/fusionAIze/faigrid/commit/cea991e94376fc75bbf2b29b6e9d28e43a650e24))

## [1.6.2](https://github.com/fusionAIze/faigrid/compare/v1.6.1...v1.6.2) (2026-04-14)


### Documentation

* reassessment — README, ROADMAP, AGENTS, cockpit spec, implementation plan ([#12](https://github.com/fusionAIze/faigrid/issues/12)) ([d28fcfc](https://github.com/fusionAIze/faigrid/commit/d28fcfca0f626d84a3968c2395da6a0e2f3c93dd))


### CI/CD

* add workflow_dispatch trigger to ci.yml ([#14](https://github.com/fusionAIze/faigrid/issues/14)) ([37c9a68](https://github.com/fusionAIze/faigrid/commit/37c9a68950f0e6fa67b0622874f131312cb9555f))

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
