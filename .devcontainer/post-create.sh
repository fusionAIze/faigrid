#!/usr/bin/env bash
set -euo pipefail

echo "[devcontainer] Installing shell tooling…"
sudo apt-get update -y -qq
sudo apt-get install -y -qq shellcheck bats

echo "[devcontainer] Installing git-cliff…"
CLIFF_VER="2.6.1"
curl -sSfL \
  "https://github.com/orhun/git-cliff/releases/download/v${CLIFF_VER}/git-cliff-${CLIFF_VER}-x86_64-unknown-linux-gnu.tar.gz" \
  | sudo tar -xz -C /usr/local/bin git-cliff/git-cliff --strip-components=1

echo "[devcontainer] Installing Python dev deps…"
pip install --quiet ruff pre-commit

echo "[devcontainer] Installing pre-commit hooks…"
pre-commit install --install-hooks

echo "[devcontainer] Dev environment ready."
