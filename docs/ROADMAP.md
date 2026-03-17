# Roadmap: fusionAIze Nexus Labs

This roadmap outlines the path from the current structured generic setup towards a fully-fledged, production-ready `v1.0.0` environment. 

The goal is to maintain the **"AI Workbench"** as an easily deployable, modular architecture without bloating the repository with unnecessary services.

---

## 📈 Versioning Strategy
- **Baseline**: `v0.0.1` is the foundational release. All subsequent development builds upon this baseline.
- **Semantic Versioning**: We use [Release Please](https://github.com/googleapis/release-please) to automatically generate releases from Conventional Commits.
- **Pre-1.0.0 Rule**: Until we reach `v1.0.0`, all new features (`feat:`) and fixes (`fix:`) will increment the **patch** or **minor** version (e.g., `v0.0.2`, `v0.1.0`). No major version bumps will occur until `v1.0.0` is explicitly released according to this roadmap. See `CONTRIBUTING.md` for commit guidelines.

---

## 🎯 v0.0.1 (Current Horizon)
*The Repository Reboot & Standardization*
- **Done:** Restructuring into the **4+1 Node Architecture** (Edge, Core, Worker, Backup, External).
- **Done:** Massive Rebranding: Moltbot mapped to native `OpenClaw` integrations.
- **Done:** GitHub Standardization: `Apache 2.0`, `release-please` automation, CI/CD testing pipelines, Community health files.
- **Done:** Implementation of the **Workbench Control Center** plugin registry (extensible CLI/Agent management).
- **Target:** Universal `install.sh` for one-click onboarding across macOS/Linux, outputting environment topology to a local config state.

---

## 🚀 v0.0.5 (Observability & Robustness)
*Making the blackbox visible.*
- **System Watchdog:** Simple systemd timers or cron jobs that alert on critical service failures (e.g., n8n container death, OpenClaw service crash).
- **Control Center V2:** Integration of log tailing directly into the `control-center.sh` terminal UI (e.g., `view logs -> n8n | foundrygate | icm`).
- **Core VNC Pipeline:** Polishing the optional TigerVNC setup for the Core instance to easily launch a graphical AI workbench overlay.

---

## 🛡️ v0.1.0 (Advanced Ingress & Security)
*Locking down the perimeter.*
- **SSO/2FA Gateways:** Automated templates for Authelia/Authentik integration at the `nexus-edge` reverse proxy level.
- **Crowdsec Bouncers:** Integration of Crowdsec with Caddy to automatically ban malicious IPs attempting to brute-force the orchestrator.
- **Internal HTTPS:** Moving the `nexus-core` from plain HTTP to internal self-signed (or local CA) TLS to encrypt traffic between Edge and Core.

---

## 🤖 v0.5.0 (The Agentic Grid)
*Unleashing the runners.*
- **Redis Queue Mode:** Activating the dormant Redis configuration to allow `nexus-core` n8n to distribute webhook invocations asynchronously to external workers.
- **Remote Model Tunneling:** Secure guides for tunneling the `nexus-worker` (e.g., old MacBook running LM Studio) into the core without exposing it to the entire LAN.
- **Extensible Webhook Definitions:** Pre-built n8n templates directly in the repo for routing tasks to FoundryGate or CLA/gemini plugins via OpenClaw.

---

## 💎 v1.0.0 (Production Blueprint)
*The final polish.*
- **GitOps Support:** Capability to deploy updates to the infrastructure directly by merging to a configuration repository (Infrastructure as Code).
- **Backup Automation:** Direct integration with Restic/Synology APIs for verified, encrypted, immutable offsite backups.
- **Node Grid Planner & Network Scanner (Interactive Mode):** An optional first step to "design" the architecture (e.g. which node gets which IP) before provisioning, possibly with a network scan to detect available target machines.
- **Telemetry Dashboards:** Extremely lightweight integration of Prometheus + Grafana for visualizing Token Consumption (from FoundryGate/ICM) and Workflow Metrics (from n8n). 
- **Pre-baked Machine Images (Post-1.0.0):** Native `.img` files for Raspberry Pi Edge nodes and Cloud-Init deployment templates for VPS instances for extreme plug-and-play onboarding. 
