#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f "README.md" ]] || [[ ! -d ".git" ]]; then
  echo "ERROR: Please run this from the repo root (where README.md and .git exist)."
  exit 1
fi

echo "[scaffold] Creating Step 02 (core) repo skeleton..."

mkdir -p docs/runbooks docs/reference docs/templates

touch \
  docs/runbooks/step-02-core-base-setup.md \
  docs/runbooks/step-02-core-macos-client.md \
  docs/runbooks/step-02-core-troubleshooting.md \
  docs/reference/ip-plan.md \
  docs/reference/naming.md \
  docs/templates/ssh-config.example \
  docs/templates/sudoers-timeout.example

mkdir -p \
  core/base/scripts \
  core/base/configs/sshd_config.d \
  core/base/configs/systemd-user \
  core/base/configs/tigervnc \
  core/base/configs/ufw \
  core/base/client/macos \
  core/base/client/ssh

touch \
  core/base/README.md \
  core/base/configs/sshd_config.d/10-grid.conf \
  core/base/configs/systemd-user/vncserver@.service \
  core/base/configs/tigervnc/config.example \
  core/base/configs/ufw/rules.md \
  core/base/client/ssh/config.snippet.example \
  core/base/client/macos/grid-vnc-ops.example \
  core/base/client/macos/grid-vnc-ops-stop.example \
  core/base/client/macos/README.md \
  core/base/scripts/ssh-hardening-apply.sh \
  core/base/scripts/ufw-apply.sh \
  core/base/scripts/vnc-install.sh \
  core/base/scripts/vnc-user-setup.sh \
  core/base/scripts/verify.sh

echo
echo "[scaffold] Done. Created/ensured the following top-level paths:"
printf "%s\n" \
  "docs/runbooks" \
  "docs/reference" \
  "docs/templates" \
  "core/base/scripts" \
  "core/base/configs" \
  "core/base/client"
echo
echo "[scaffold] Next recommended step:"
echo "  git status"
echo "  git add docs core"
echo "  git commit -m \"scaffold: add Step 02 core base skeleton\""
