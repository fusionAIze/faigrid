# Core Onboarding & Lab Setup (nexus-core)

The `nexus-core` instance is the heart of your automation and AI capabilities. It acts as an **AI Workbench** and **Routing Node** for your various tools, internal processes, and virtual agents.

This document serves as an onboarding guide to understand the scope of the core environment, what tools are supported, and how configuration is completely decoupled from the codebase.

## 1. Environment Philosophy

To maintain a secure, generic, and reproducible infrastructure, **no secrets or specific configurations live in the code repository.** 

- Configuration relies purely on environment variables (`.env`).
- Example configuration templates (e.g., `.env.example`) provide generic placeholders.
- The actual state of the core logic, API keys, database credentials, and routing rules live purely on the server in protected `.env` files (e.g., `/opt/fusionaize-nexus/core-heart/.env`).

This separation ensures the repo acts as a structural reference, while deployment remains flexible—whether bare-metal on a Mini-PC, virtualized, or in the cloud.

## 2. Supported Workbench Tooling

The core instance integrates several critical components acting as your central AI nervous system.

### Automation
- **Internal n8n**: The core automation and workflow engine. Built primarily for internal processes and integrations. It is *not* exposed to the public internet. External requests route either through `nexus-edge` or from your `nexus-external` cloud instance.

### Orchestration & Routing
- **OpenClaw**: The host-native agent dispatcher running on the system, used to map and control deployed AI agents.
- **FoundryGate / ICM / RTK**: Internal router layers responsible for token-consumption optimization, context-memory management, and distributing inference tasks to either local models (`nexus-worker`) or cloud models.

### CLI Agents & Toolkits
The Core host provides a lab environment for cutting-edge agentic workflows:
- `kilo`, `gemini`, `claude`, `codex`
- [Google Workspace CLI](https://github.com/googleworkspace/cli)
- [CLI-Anything](https://github.com/HKUDS/CLI-Anything)
- [Paperclip](https://github.com/paperclipai/paperclip)
- [Ship-Faster](https://github.com/stevejenkins/pi-hole-lists)
- [SWE-AF](https://github.com/Agent-Field/SWE-AF)

## 3. Onboarding Steps

When bringing a new `nexus-core` instance online, follow these high-level steps:

1. **Deploy the Base System**: Complete the SSH hardening and basic user setup defined in `step-02-core-base-setup.md`.
2. **Install Core Services**: Instantiate the Postgres, Redis (queue), and n8n stack defined in `core/heart/compose`. Ensure all `.env` credentials are securely generated.
3. **Establish Routing**: Deploy FoundryGate and RTK via Docker or node as defined in their independent configurations, exposing them locally on the internal Docker network or `127.0.0.1`.
4. **Deploy OpenClaw**: Follow the native service installation via `core/openclaw/native/server/control-center.sh` and bind it to specific router endpoints.
5. **Install CLI Tools**: System-wide installation of the required agent CLI toolkits (e.g., Python `pipx` installs or NPM global installs) into the execution user’s environment (`nexus-runner`).
6. **Connect the Edge**: Update the Pi Edge (Caddy) to create secure, SSO-gated tunnels for dashboard access to n8n and OpenClaw.
