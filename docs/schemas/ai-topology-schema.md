# AI-Native Deployment Schema (`ai-topology.json`)

To orchestrate the **fusionAIze Nexus Labs** autonomously, an AI Agent (Codex, Claude, etc.) should construct a `topology.json` file and pass it to the `scripts/ai-deploy.sh` executable.

## Execution Pattern

1. **Agent Step**: Determine target mapping (e.g. from user prompt or `.env.topology`).
2. **Agent Step**: Generate `payload.json` file anywhere on disk.
3. **Agent Step**: Execute `bash scripts/ai-deploy.sh payload.json`. The orchestrator will autonomously execute the `install.sh` sequence across all listed nodes.

## JSON Payload Schema Structure

```json
{
  "global": {
    "force_overwrite": "true" 
  },
  "nodes": [
    {
      "role": "core",
      "ssh_target": "user@10.0.0.100",
      "strategy": "2"
    },
    {
      "role": "edge",
      "ssh_target": null,
      "strategy": "1"
    }
  ]
}
```

### Parameter Details

*   **`global.force_overwrite`** (string: `"true"` | `"false"`):
    *   If `"true"`, it passes the `--yes` flag to `install.sh`, autonomously overcoming destructive overwrite prompts during `Fresh Install` (Strategy 2). Extremely powerful.
*   **`nodes[].role`** (string - REQUIRED):
    *   Accepts: `"edge"`, `"core"`, `"worker"`, `"backup"`, `"external"`.
*   **`nodes[].strategy`** (string):
    *   `"1"`: Extend / Update Existing Infra.
    *   `"2"`: Fresh Install (Overwrite).
    *   `"3"`: Guided Wizard. *Note: Usually not recommended for AI payload mode as it introduces interactive hardware validations.*
*   **`nodes[].ssh_target`** (string | `null`):
    *   Provide the SSH connection string (e.g. `pi@192.168.1.100`).
    *   Provide `null` or omit the key to trigger local installation on the machine executing `ai-deploy.sh`.
