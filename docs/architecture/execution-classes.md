# Execution Classes in fusionAIze Grid

**fusionAIze Grid (faigrid)** fundamentally structures AI-native operations around **Execution Classes** rather than hardware. 

An Execution Class defines the permissions, network isolation, compute limits, and observability posture for a specific type of AI workload.

## The Classes

### 1. Edge Ingress Workloads (`grid-edge`)
- **Purpose**: Public intake, TLS termination, Reverse Proxy (Caddy), Identity (SSO/CrowdSec).
- **Topology**: The only class exposed to the public internet on ports 80/443.
- **Constraints**: No database access. Forwarding logic only. Extremely fast restarts.

### 2. Trusted Internal Services (`grid-core`)
- **Purpose**: Internal APIs, orchestration helpers (n8n, OpenClaw UI), coordination services (Postgres, Redis).
- **Topology**: Private network only (`grid_net`). No public exposure.
- **Constraints**: Services here hold the "keys to the kingdom". Workloads here are fully trusted. Secrets are exposed only to these containers.

### 3. Queued Automations
- **Purpose**: Asynchronous workflows, event-driven tasks, delayed actions (n8n workers).
- **Topology**: Consume from Redis queues within the `grid_net`.
- **Constraints**: Must be idempotent where possible. Log output must trace directly to a workflow ID.

### 4. Privileged Runners
- **Purpose**: System-level actions that mutate the Grid itself (deployment tasks, infra updates, repo changes).
- **Topology**: Often script-based wrappers using `sudo` locally, or highly credentialed containers.
- **Constraints**: Requires strict explicit approval biases or post-review tracking.

### 5. Shell & Browser Runners (`core/runners`)
- **Purpose**: Isolated task execution for agents. When an agent needs to execute Python code, run `git`, or scrape a website using Playwright, it executes *here*, not in `grid-core`.
- **Topology**: Isolated Docker networks (`grid_runner_net`). Egress allowed (for fetching data), but strictly bounded. 
- **Constraints**: CPU and Memory are strictly capped using Docker limits. Priveleges are dropped (`cap_drop: ALL`).

### 6. Local Model Workers (`grid-worker`)
- **Purpose**: LAN-only inference (LM Studio, Ollama). 
- **Topology**: Private network instances. Connected via Tailscale or direct LAN routes back to `grid-core`.
- **Constraints**: No direct public ingress. Usually heavy GPU dependency.

### 7. Cloud Model Bridges (`grid-external`)
- **Purpose**: Egress pipelines to OpenRouter, Anthropic, OpenAI, etc.
- **Topology**: API calls brokered ideally through `fusionAIze Gate` (`faigate`) for token optimization.
- **Constraints**: Measured cost surfaces. Credentials tightly scoped.

---

## Implementing Runners

When using autonomous agents (e.g., via OpenClaw), code execution must be decoupled.
Instead of the agent executing `python script.py` natively on the host, it should dispatch to a runner:

```bash
docker exec grid-shell-runner bash -c "python3 /workspace/script.py"
```

See `core/runners/shell-runner` and `core/runners/browser-runner` for pre-configured blueprints.
