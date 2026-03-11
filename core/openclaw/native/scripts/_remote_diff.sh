#!/usr/bin/env bash
set -euo pipefail

# Shared helpers for OpenClaw prod push scripts (macOS).
# Safe-by-default: no secrets printed.

die(){ echo "ERROR: $*" >&2; exit 1; }
need_cmd(){ command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

need_cmd ssh
need_cmd awk
need_cmd sed
need_cmd grep
need_cmd diff

sha256_file() {
  local f="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" | awk '{print $1}'
  else
    sha256sum "$f" | awk '{print $1}'
  fi
}

sanitize_json_local() {
  local in="$1" out="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -S 'del(
      .channels.telegram.botToken,
      .channels.discord.token,
      .models.providers.deepseek.apiKey,
      .models.providers.google.apiKey,
      .models.providers.openai.apiKey,
      .models.providers.openrouter.apiKey
    )' "$in" > "$out"
  else
    cp -f "$in" "$out"
  fi
}

env_key_status_local() {
  local f="$1"
  [ -f "$f" ] || die "Missing local env file: $f"
  awk -F= '
    /^[A-Z0-9_]+=/ {
      key=$1;
      val=$0; sub(/^[^=]*=/,"",val);
      if (length(val)>0) print key"=SET"; else print key"=EMPTY";
    }
  ' "$f" | sort
}

require_remote_sudo_n() {
  local host="$1"
  if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" "sudo -n true" >/dev/null 2>&1; then
    cat >&2 <<MSG
ERROR: sudo -n is not permitted on $host (would hang).
Run this once (interactive) to refresh sudo:
  ssh -tt $host 'sudo -v'
Then rerun the push script.
MSG
    exit 1
  fi
}

sanitize_json_remote_to_local() {
  local host="$1" remote_path="$2" local_out="$3"
  require_remote_sudo_n "$host"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" "sudo -n cat '$remote_path'" \
  | (command -v jq >/dev/null 2>&1 && jq -S 'del(
        .channels.telegram.botToken,
        .channels.discord.token,
        .models.providers.deepseek.apiKey,
        .models.providers.google.apiKey,
        .models.providers.openai.apiKey,
        .models.providers.openrouter.apiKey
      )' || cat) \
  > "$local_out"
}

env_key_status_remote() {
  local host="$1" remote_path="$2"
  require_remote_sudo_n "$host"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" "sudo -n awk -F= '
    /^[A-Z0-9_]+=/ {
      key=\$1;
      val=\$0; sub(/^[^=]*=/,\"\",val);
      if (length(val)>0) print key\"=SET\"; else print key\"=EMPTY\";
    }
  ' '$remote_path' | sort"
}

# --- Backup helpers (remote) ---

remote_mk_backup_dir() {
  local host="$1" base_dir="$2"
  require_remote_sudo_n "$host"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" "sudo -n install -d -m 0700 '$base_dir' && echo '$base_dir'"
}

remote_backup_file() {
  local host="$1" src="$2" dst_dir="$3" name="$4"
  require_remote_sudo_n "$host"
  # backup only if exists and non-empty
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" "sudo -n bash -lc '
    set -euo pipefail
    if [ -s \"$src\" ]; then
      cp -a \"$src\" \"$dst_dir/$name\"
      echo \"BACKUP: $src -> $dst_dir/$name\"
    else
      echo \"BACKUP: $src missing/empty -> skipped\"
    fi
  '"
}

remote_restore_file() {
  local host="$1" backup="$2" dst="$3" owner="$4" mode="$5"
  require_remote_sudo_n "$host"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" "sudo -n bash -lc '
    set -euo pipefail
    [ -s \"$backup\" ] || { echo \"RESTORE: backup missing $backup\"; exit 2; }
    cp -a \"$backup\" \"$dst\"
    chown $owner \"$dst\"
    chmod $mode \"$dst\"
    echo \"RESTORE: $dst <- $backup\"
  '"
}

remote_restart_openclaw() {
  local host="$1"
  require_remote_sudo_n "$host"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" "sudo -n systemctl restart openclaw.service"
}

# --- Health checks (remote) ---
# NOTE: We use "grep" checks on the CLI output to avoid relying on exit codes only.

remote_healthcheck() {
  local host="$1"
  require_remote_sudo_n "$host"

  echo "== HEALTH: systemd active? =="
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" "sudo -n systemctl is-active openclaw.service"

  echo
  echo "== HEALTH: channels status (probe) =="
  # Print the first lines for visibility (no secrets)
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" \
    "ocprod channels status --probe | sed -n '1,140p'"

  # Hard requirements: both show "works"
  if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" \
      "ocprod channels status --probe | grep -Eqi 'Telegram .*works'"; then
    echo "HEALTH FAIL: Telegram not 'works'" >&2
    return 10
  fi
  if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" \
      "ocprod channels status --probe | grep -Eqi 'Discord .*works'"; then
    echo "HEALTH FAIL: Discord not 'works'" >&2
    return 11
  fi

  echo
  echo "== HEALTH: models probe (short) =="
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" \
    "ocprod models status --probe --probe-max-tokens 8 | sed -n '1,140p'"

  # Require "Probed" line and no obvious errors
  if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" \
      "ocprod models status --probe --probe-max-tokens 8 | grep -Eqi '^Probed [0-9]+'"; then
    echo "HEALTH FAIL: models probe did not complete" >&2
    return 12
  fi
  if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" \
      "ocprod models status --probe --probe-max-tokens 8 | grep -Eqi 'Config invalid|Error:|FAILED|unauthorized'"; then
    echo "HEALTH FAIL: models output contains error markers" >&2
    return 13
  fi

  echo
  echo "OK: HEALTHCHECK passed."
  return 0
}
