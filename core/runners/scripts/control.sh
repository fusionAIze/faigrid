#!/usr/bin/env bash
# ==============================================================================
# grid-runner : Lifecycle control
# ==============================================================================
set -euo pipefail

ACTION="${1:-status}"

cd "$(dirname "$0")/.."

for runner in shell-runner browser-runner; do
    if [[ -d "$runner" ]]; then
        echo "[runner ($ACTION)] $runner"
        case "$ACTION" in
            start)
                cd "$runner" && docker compose up -d && cd ..
                ;;
            stop)
                cd "$runner" && docker compose stop && cd ..
                ;;
            restart)
                cd "$runner" && docker compose restart && cd ..
                ;;
            status)
                cd "$runner" && docker compose ps && cd ..
                ;;
            *)
                echo "Unknown action: $ACTION"
                ;;
        esac
    fi
done
