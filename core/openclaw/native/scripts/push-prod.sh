#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_remote_diff.sh
source "$DIR/_remote_diff.sh"

HOST_ALIAS="${HOST_ALIAS:-nexus-core}"
APPLY="false"
RESTART="false"
VERIFY="true"
NO_ROLLBACK="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY="true"; shift ;;
    --restart) RESTART="true"; shift ;;
    --no-verify) VERIFY="false"; shift ;;
    --no-rollback) NO_ROLLBACK="true"; shift ;;
    --host) HOST_ALIAS="$2"; shift 2 ;;
    -h|--help)
      cat <<USAGE
Usage:
  HOST_ALIAS=nexus-core $0
  HOST_ALIAS=nexus-core $0 --apply --restart
Options:
  --apply         actually write env + config to server
  --restart       restart openclaw after apply
  --no-verify     skip post-apply healthcheck
  --no-rollback   do not rollback on failed healthcheck
  --host <alias>  SSH host alias
Notes:
  This requires LOCAL secrets file (gitignored):
    core/openclaw/env/openclaw.providers.env
USAGE
      exit 0
      ;;
    *) die "Unknown arg: $1" ;;
  esac
done

LOCAL_CFG="core/openclaw/native/configs/openclaw.json.golden.example"
LOCAL_ENV="core/openclaw/env/openclaw.providers.env"   # gitignored, must exist with real values
REMOTE_CFG="/var/lib/openclaw/.openclaw-prod/openclaw.json"
REMOTE_ENV="/etc/openclaw/openclaw.providers.env"

[ -f "$LOCAL_CFG" ] || die "Missing: $LOCAL_CFG"
[ -f "$LOCAL_ENV" ] || die "Missing local secrets env: $LOCAL_ENV (copy from .example and fill values)."

# Safety: refuse apply if required vars are empty
REQUIRED_VARS=(
  DEEPSEEK_API_KEY
  GEMINI_API_KEY
  OPENAI_API_KEY
  TELEGRAM_BOT_TOKEN
  DISCORD_BOT_TOKEN
)

missing=0
for k in "${REQUIRED_VARS[@]}"; do
  line="$(grep -E "^${k}=" "$LOCAL_ENV" || true)"
  val="${line#*=}"
  if [ -z "${line:-}" ] || [ -z "${val:-}" ]; then
    echo "ENV CHECK: $k=EMPTY"
    missing=$((missing+1))
  else
    echo "ENV CHECK: $k=SET"
  fi
done

if [ "$missing" -gt 0 ]; then
  die "Local env has $missing EMPTY required vars. Refusing."
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
local_san="$tmpdir/local.san.json"
remote_san="$tmpdir/remote.san.json"
sanitize_json_local "$LOCAL_CFG" "$local_san"

echo
echo "== Target host: $HOST_ALIAS =="
echo "Remote cfg: $REMOTE_CFG"
echo "Remote env: $REMOTE_ENV"
echo "Local  cfg: $LOCAL_CFG"
echo "Local  env: $LOCAL_ENV"
echo

echo "== Diff: config (sanitized) =="
if sanitize_json_remote_to_local "$HOST_ALIAS" "$REMOTE_CFG" "$remote_san" 2>/dev/null; then
  diff -u "$remote_san" "$local_san" || true
else
  echo "(no remote config to diff)"
fi

echo
echo "== Diff: env (KEY=SET/EMPTY only) =="
remote_env_keys="$tmpdir/remote.env.keys"
local_env_keys="$tmpdir/local.env.keys"
if env_key_status_remote "$HOST_ALIAS" "$REMOTE_ENV" > "$remote_env_keys" 2>/dev/null; then
  env_key_status_local "$LOCAL_ENV" > "$local_env_keys"
  diff -u "$remote_env_keys" "$local_env_keys" || true
else
  echo "(no remote env to diff)"
fi

echo
if [ "$APPLY" != "true" ]; then
  echo "DRY RUN only. Re-run with: $0 --apply [--restart]"
  exit 0
fi

require_remote_sudo_n "$HOST_ALIAS"

TS="$(date +%F_%H%M%S)"
BKP_CFG_DIR="/var/lib/openclaw/.openclaw-prod/_backup_repo_push/$TS"
BKP_ENV_DIR="/etc/openclaw/_backup_repo_push/$TS"
remote_mk_backup_dir "$HOST_ALIAS" "$BKP_CFG_DIR" >/dev/null
remote_mk_backup_dir "$HOST_ALIAS" "$BKP_ENV_DIR" >/dev/null

remote_backup_file "$HOST_ALIAS" "$REMOTE_CFG" "$BKP_CFG_DIR" "openclaw.json.bak"
remote_backup_file "$HOST_ALIAS" "$REMOTE_ENV" "$BKP_ENV_DIR" "openclaw.providers.env.bak"

echo
echo "== APPLY: write env (0640 root:openclaw, dir 0750) =="
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$HOST_ALIAS" \
  "sudo -n install -d -m 0750 -o root -g openclaw /etc/openclaw"

cat "$LOCAL_ENV" | ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$HOST_ALIAS" \
  "sudo -n tee '$REMOTE_ENV' >/dev/null"

ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$HOST_ALIAS" \
  "sudo -n chown root:openclaw '$REMOTE_ENV' && sudo -n chmod 0640 '$REMOTE_ENV'"

echo "OK: env written."

echo
echo "== APPLY: write config (0600 openclaw:openclaw) =="
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$HOST_ALIAS" \
  "sudo -n install -d -m 0700 -o openclaw -g openclaw /var/lib/openclaw/.openclaw-prod"

cat "$LOCAL_CFG" | ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$HOST_ALIAS" \
  "sudo -n tee '$REMOTE_CFG' >/dev/null"

ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$HOST_ALIAS" \
  "sudo -n chown openclaw:openclaw '$REMOTE_CFG' && sudo -n chmod 600 '$REMOTE_CFG'"

echo "OK: config written."

if [ "$RESTART" = "true" ]; then
  echo "== Restart openclaw.service =="
  remote_restart_openclaw "$HOST_ALIAS"
fi

if [ "$VERIFY" = "true" ]; then
  echo
  echo "== POST-VERIFY (healthcheck) =="
  if ! remote_healthcheck "$HOST_ALIAS"; then
    echo "POST-VERIFY FAILED." >&2
    if [ "$NO_ROLLBACK" = "true" ]; then
      echo "Rollback disabled (--no-rollback). Leaving system as-is." >&2
      exit 30
    fi

    echo
    echo "== AUTO-ROLLBACK: restore previous env + config =="
    # restore env first, then cfg
    remote_restore_file "$HOST_ALIAS" "$BKP_ENV_DIR/openclaw.providers.env.bak" "$REMOTE_ENV" "root:openclaw" "640"
    remote_restore_file "$HOST_ALIAS" "$BKP_CFG_DIR/openclaw.json.bak" "$REMOTE_CFG" "openclaw:openclaw" "600"

    echo "== Restart openclaw.service (after rollback) =="
    remote_restart_openclaw "$HOST_ALIAS"
    echo "== Healthcheck after rollback =="
    remote_healthcheck "$HOST_ALIAS" || true

    exit 31
  fi
fi

echo "DONE."
