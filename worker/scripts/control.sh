#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"

case "$ACTION" in
  start|stop|restart|status)
    if command -v ollama &> /dev/null; then
        echo "[grid-worker] Managing Ollama..."
        # On macOS, Ollama is usually an app or brew service
        if [[ "$(uname -s)" == "Darwin" ]]; then
            brew services "$ACTION" ollama || echo "Ollama not managed by brew services. Please use the Ollama App."
        else
            sudo systemctl "$ACTION" ollama
        fi
    fi
    if command -v lms &> /dev/null; then
        echo "[grid-worker] LM Studio (lms) status check..."
        lms status || true
    fi
    ;;
  install)   bash "$(dirname "$0")/install.sh" ;;
  update)    bash "$(dirname "$0")/update.sh" ;;
  verify)    bash "$(dirname "$0")/verify.sh" ;;
  uninstall) bash "$(dirname "$0")/uninstall.sh" ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|install|update|verify|uninstall}"
    exit 1
    ;;
esac
