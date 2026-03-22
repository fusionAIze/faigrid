# Roadmap: fusionAIze Grid (formerly fusionAIze Grid)

This roadmap outlines the path from the current structured orchestrator base towards the fully-fledged, production-ready **fusionAIze Grid**. 

## 🌌 The fusionAIze Vision & Role Architecture

**fusionAIze** is the operating brand for *human-AI fusion teams*. The ecosystem connects live execution environments, memory fabrics, and routing protocols.

This repository will become **fusionAIze Grid**:
> **The sovereign execution environment for private, public and hybrid AI operations.**
> Directly interfacing with workflows, CLI stacks, automation servers (like n8n), and deploying AI workloads locally or remotely.

### The Unified Product Stack
1. **fusionAIze Gate (faigate):** The AI-native gateway for models, providers, tools, and clients.
2. **fusionAIze Lens:** The relevance, compression, and context-focusing layer.
3. **fusionAIze Fabric:** The shared context, memory, and knowledge fabric.
4. **fusionAIze Grid (faigrid):** The overarching sovereign execution environment (this repo).
5. **fusionAIzeOS:** The orchestration layer for cross-workflow scaling.

### Architectural Blueprint (The 4+1 Nodes within the Grid)
The Grid is built on abstraction rather than hardware coupling. It provisions and connects:
- **core:** The Orchestrator and Agentic Hub (n8n, PostgreSQL, Redis, APIs).
- **edge:** TLS ingress, dynamic routing (Caddy), Identity, and Access Control.
- **worker:** Compute environments scaling Local Inference (LM Studio, Ollama).
- **backup:** The state preserver (immutable snapshotting to local disks, NAS, or S3).
- **external:** Proxied routing to public cloud services, preserving the sovereign core.

---

## 📈 Versioning & Migration Strategy

We build upon standard Semantic Versioning, with **`v1.3.0` forming the bridging milestone.**
Only after reaching the solid `v1.3.0` checkpoint will this repository undergo a complete rename and strict decoupling from its historical "fusionAIze Grid" identity.

- **Current Status:** Consolidating UX loops, CLI registry patterns, and `faigate` template ingestion.
- **Next Horizon:** Reaching `v1.3.0-dev` stabilization.
- **After 1.3.0:** Full in-repo rebranding to `faigrid` (`fusionAIze/faigrid`), mirroring the clean state of `faigate`.

---

## ⚖️ Component & Licensing Map (v1)

We are adopting a **Hybrid Framework** balancing *wide developer adoption* with *defensible enterprise differentiation*:
- **Open / Apache 2.0 (Tier A):** Boilerplate templates, sample docker configs, standard integrations. Openly distributed to ensure maximum ecosystem adoption.
- **Open-Core / Source-Available (Tier B):** Managed deployment packs, topology controllers, and orchestration modules bridging basic execution and specialized tasks.
- **Proprietary / Commercial (Tier C):** Identity routing, Enterprise Governance recipes, compliance clusters, and managed operational logic for the `fusionAIze Services` branches.

## 🚀 Execution Horizons

### Phase 1: Refining the Foundation (Current – v1.3.0)
*Securing the baseline and aligning with the Gateway.*
- [x] Integrate **fusionAIze Gate** into the orchestration wizard.
- [x] Standardize interactive installer with specific pipx-bootstrapping and local node detection logic.
- [ ] Stabilize and align plugin ecosystem for memory (mem0), routers (openrouter), and agents (openclaw).
- [ ] Solidify `.grid-state` into `.grid-state` mapping.
- [ ] Prepare repository for clean git decoupling.

### Phase 2: Complete Rebrand to *fusionAIze Grid* 
*The naming and identity shift (Post-1.3.0)*
- Execution of the deep repository rename: `typelicious/faigrid` → `fusionAIze/faigrid` (Manual transfer, then full string replacement).
- Systematic removal of legacy `fusionAIze Grid` phrasing outside of necessary architectural roles (`grid-edge`, `grid-core`).
- Establishing the `brew install faigrid` installer pipeline for frictionless macOS and Linux setups.
- Deep alignment of UI terminal structures with `faigate` for matching operational UX.

### Phase 3: The Sovereign Orchestrator 
*Enhancing the premium Grid topologies.*
- Implement cross-node dynamic scaling via Redis queues (dispatching webhooks natively to local workers).
- Introduce Identity Layers via Authentik/Authelia templates (the beginning of Tier C).
- Introduce interactive telemetry dashboards bridging Gate token consumption with Grid automation workflows.

### Phase 4: GitOps & Infrastructure as Code (v2.0)
*Enabling fully auditable hybrid deployments.*
- Immutable state definitions ensuring Grid environments can be reconstructed from zero to production purely via Git references.
- Full backup resilience utilizing orchestrated Synology integration.
- Remote tunneling logic ensuring isolated `workers` can securely interface with a public `core`.
