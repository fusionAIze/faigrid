# Roadmap: fusionAIze Grid (faigrid)

This roadmap outlines the path from the current baseline towards the fully-fledged, production-ready **fusionAIze Grid v3**.

---

## 🌌 The fusionAIze Vision & Role Architecture

**fusionAIze** builds, operates, and enables *human-AI fusion teams*. The ecosystem connects live execution environments, memory fabrics, and team operating logic to turn AI from an isolated capability into operational collaboration.

### The Component Map (Core Now)
The current, narrowest, and strongest product spine consists of:
1. **fusionAIze Gate:** The AI-native gateway for models, providers, tools, and clients. *(Connects)*
2. **fusionAIze Lens:** The relevance, compression, translation, and explanation layer. *(Filters & Shapes)*
3. **fusionAIze Fabric:** The shared context, memory, and knowledge fabric. *(Remembers & Serves)*
4. **fusionAIze Grid (`faigrid`):** The sovereign execution substrate (this repo). *(Runs)*
5. **fusionAIzeOS:** The operating logic for human-AI fusion teams. *(Defines Coworker Reality)*

*(Likely Later: **Signal** as an operational intelligence layer, and **Studio** for blueprint authoring).*

---

## 💠 The True Position of fusionAIze Grid

> **fusionAIze Grid is the sovereign execution substrate for AI-native operations across local, on-prem, private cloud, public cloud, and hybrid deployments.**

Its job is to define **where** AI-native work runs, under **what constraints**, with **what isolation**, through which **queues/runners**, and with which **secrets, observability, and backup patterns**. It is the execution layer, not the context, memory, or overarching OS layer.

### The Product Primitives
Grid moves beyond hardware abstractions and focuses on **Execution Classes** and **Deployment Profiles**:

**Execution Classes:**
- Edge Ingress Workloads (Public intake, Caddy, Auth)
- Trusted Internal Services (n8n, APIs)
- Queued Automations
- Privileged Runners (System-level operations)
- Browser & Shell Runners (Isolated task execution)
- Local Model Workers (LAN-only inference)
- Cloud Model Bridges (Routed external reasoning)

**Deployment Profiles:**
1. **Solo Operator**: Local-first, practical, low complexity.
2. **Small Team**: Shared internal services, basic queues, backups.
3. **SMB**: Stricter runners, hybrid local/cloud placement, strong isolation.
4. *(Later)* **Enterprise**: Compliance-heavy, rich policy layers.

---

## 📈 Versioning & Execution Horizons

We build upon standard Semantic Versioning, with **`v1.3.0` forming the bridging milestone.**

- **Current Status**: Eradicated legacy identity. Consolidating the basic runtime topology.
- **Next Horizon**: Formalizing the distinct **Execution Classes** within the established 4+1 node architecture.

### Phase 1: Refining the Foundation (Current – v1.3.0)
*Securing the baseline and proving the standalone value.*
- [x] Standardize interactive installer with clear edge/core separation.
- [x] Eradicate legacy terminology and align fully with the fusionAIze brand.
- [x] Stabilize basic plugin ecosystem (mem0, openrouter) as isolated primitives.
- [ ] Formalize **Queue & Runner Discipline** for asynchronous agents.
- [ ] Harden **Observability & Backup Layer** defaults (Logs, Metrics, Snapshotting).

### Phase 2: Execution Classes & Small-Team Operations (v2.0)
*Moving from "clever setup" to durable operational substrate.*
- Establish clear runner boundaries (Browser Runners, Shell Runners, Privileged Runners).
- Hybrid Model bridging: Seamless orchestration between Cloud Bridges (via faigate) and Local Workers.
- GitOps implementation for declarative execution topology definitions.
- Implement explicit Deployment Profiles (Solo Operator -> Small Team templates).

### Phase 3: Service Grid & Productization
*Supporting Agency scaling and managed editions.*
- Richer execution classes for multi-project isolation.
- Integration hooks for future `fusionAIze Signal` (Operational Intelligence / Telemetry).
- Seamless adapter endpoints for `fusionAIzeOS` to inject role-aware collaboration logic into the Grid runners.
- Plug-support for external secure runtimes (NemoClaw-inspired execution boundaries / OpenShell adapters).
