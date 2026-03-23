#!/usr/bin/env bash
# ==============================================================================
# grid-runner : install payload
# ==============================================================================
set -euo pipefail

echo "============================================================"
echo " Bootstrapping Validated execution runners"
echo "============================================================"

# Change to the runners directory relative to the script
cd "$(dirname "$0")/.."

for runner in shell-runner browser-runner; do
    if [[ -f "$runner/docker-compose.yml" ]]; then
        echo " -> Starting Docker Compose stack for isolated [${runner}]..."
        cd "$runner"
        # Pull images explicitly
        docker compose pull
        docker compose up -d
        cd ..
    fi
done

echo ""
echo "  [OK] Runner Substrate deployed successfully."
echo "  Agents and automation can now securely execute commands inside the runners using:"
echo "    docker exec grid-shell-runner bash -c '...'"
echo "============================================================"
