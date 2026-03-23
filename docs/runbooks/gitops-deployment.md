# GitOps Deployment Pipeline

**fusionAIze Grid (v3)** is designed as an explicitly definable Infrastructure as Code (IaC) substrate for AI teams. 

Unlike heavy Kubernetes environments requiring Flux or ArgoCD, the faigrid "Macher-Fokus" enables fully declarative pipelines using a single JSON payload and standard CI/CD tools (like GitHub Actions), without requiring dedicated cluster agents.

## 1. The Declarative Engine

The master deployment engine is `scripts/grid-deploy.sh`. 
It ingests a `topology.json` file and handles all SSH tunneling, staging, and parallel deployments headlessly.

### Structure of `topology.json`

```json
{
    "global": {
        "force_overwrite": "true"
    },
    "nodes": [
        {
            "role": "core",
            "strategy": "1",
            "ssh_target": "grid@192.168.178.20"
        },
        {
            "role": "runner",
            "strategy": "1",
            "ssh_target": "grid@192.168.178.20"
        }
    ]
}
```
*Tip: See `docs/examples/topology-smb.json` for a fully scaled Small Business multi-node layout.*

## 2. Infrastructure as Code Repository

To manage your Grid via GitOps:
1. Create a private repository for your organization (e.g., `acme-grid-infrastructure`).
2. Add your custom `topology.json` to the root.
3. Configure your CI/CD pipeline (see below).

## 3. GitHub Actions Pipeline Example

This action runs every time you modify `topology.json`. It securely pulls the central `faigrid` engine, copies your topology into it, and triggers the orchestrator.

```yaml
name: "Deploy Grid Topology"
on:
  push:
    branches: ["main"]
    paths:
      - 'topology.json'

jobs:
  deploy-grid:
    runs-on: ubuntu-latest
    steps:
      - name: "Checkout Org State"
        uses: actions/checkout@v4
      
      - name: "Checkout faigrid Engine"
        uses: actions/checkout@v4
        with:
          repository: typelicious/faigrid
          path: faigrid
          
      - name: "Move Topology"
        run: cp topology.json faigrid/
      
      - name: "Setup SSH Key"
        uses: webfactory/ssh-agent@v0.8.0
        with:
          ssh-private-key: ${{ secrets.GRID_SSH_PRIVATE_KEY }}
          
      - name: "Execute GitOps Deployment"
        run: |
          cd faigrid
          bash scripts/grid-deploy.sh topology.json
```

## 4. Secure Secrets Injection

**Never commit `grid.env` or API Keys to Git.**

If your pipeline requires injecting production credentials:
1. Store keys in **GitHub Actions Secrets**.
2. Have the runner securely inject them directly into the remote Nodes *before* running `grid-deploy.sh`.

```yaml
      - name: "Inject Core Secrets"
        run: |
          echo "OPENAI_API_KEY=${{ secrets.OPENAI_API_KEY }}" > .env.core
          scp .env.core grid@192.168.178.20:~/.config/faigrid/grid.env
          rm .env.core
```

When `grid-deploy.sh` reaches the `192.168.178.20` node, it will naturally pick up the freshly injected `.config/faigrid/grid.env` file and provision the N8N/OpenClaw environments perfectly.
