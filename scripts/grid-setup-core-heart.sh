#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f "README.md" ]] || [[ ! -d ".git" ]]; then
  echo "ERROR: run from repo root (README.md + .git must exist)."
  exit 1
fi

echo "[scaffold] Creating Step 03 (core heart) repo skeleton..."

mkdir -p \
  core/heart/compose \
  core/heart/scripts \
  core/heart/configs/caddy \
  core/heart/configs/n8n \
  core/heart/configs/postgres \
  core/heart/configs/redis \
  core/heart/configs/openclaw \
  core/heart/backups/.gitkeep \
  docs/runbooks \
  docs/reference \
  docs/templates

touch \
  core/heart/README.md \
  core/heart/compose/docker-compose.yml \
  core/heart/compose/.env.example \
  core/heart/compose/.env.local.example \
  core/heart/configs/caddy/Caddyfile.example \
  core/heart/scripts/control-center.sh \
  core/heart/scripts/install.sh \
  core/heart/scripts/update.sh \
  core/heart/scripts/backup.sh \
  core/heart/scripts/restore.sh \
  core/heart/scripts/verify.sh \
  docs/runbooks/step-03-core-heart-stack.md \
  docs/reference/ports.md \
  docs/reference/credentials.md \
  docs/templates/systemd-grid-heart.example

echo "[scaffold] Done."
