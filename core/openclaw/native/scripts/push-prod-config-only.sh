#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_remote_diff.sh
source "$DIR/_remote_diff.sh"

HOST_ALIAS="${HOST_ALIAS:-grid-core}"
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
  HOST_ALIAS=grid-core $0
  HOST_ALIAS=grid-core $0 --apply --restart
Options:
  --apply         actually write to server
  --restart       restart openclaw after apply
  --no-verify     skip post-apply healthcheck
  --no-rollback   do not rollback on failed healthcheck
  --host <alias>  SSH host alias
USAGE
      exit 0
      ;;
    *) die "Unknown arg: $1" ;;
  esac
done

LOCAL_CFG="core/openclaw/native/configs/openclaw.json.golden.example"
REMOTE_CFG="/var/lib/openclaw/.openclaw-prod/openclaw.json"

[ -f "$LOCAL_CFG" ] || die "Missing: $LOCAL_CFG"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
local_san="$tmpdir/local.san.json"
remote_san="$tmpdir/remote.san.json"

sanitize_json_local "$LOCAL_CFG" "$local_san"

echo "== Target host: $HOST_ALIAS =="
echo "== Local config:  $LOCAL_CFG =="
echo "== Remote config: $REMOTE_CFG =="
echo

# Try remote sanitized fetch for diff
if sanitize_json_remote_to_local "$HOST_ALIAS" "$REMOTE_CFG" "$remote_san" 2>/dev/null; then
  echo "Remote config: present"
else
  echo "Remote config: missing/unreadable (needs sudo -n)."
  echo "Tip: ssh -tt $HOST_ALIAS 'sudo -v'"
fi

echo
echo "== Hashes (sanitized JSON) =="
echo "local : $(sha256_file "$local_san")"
if [ -s "$remote_san" ]; then
  echo "remote: $(sha256_file "$remote_san")"
else
  echo "remote: (n/a)"
fi

echo
echo "== Diff (sanitized) =="
if [ -s "$remote_san" ]; then
  diff -u "$remote_san" "$local_san" || true
else
  echo "(no remote to diff)"
fi

echo
if [ "$APPLY" != "true" ]; then
  echo "DRY RUN only. Re-run with: $0 --apply [--restart]"
  exit 0
fi

require_remote_sudo_n "$HOST_ALIAS"

# Backup dir (remote)
TS="$(date +%F_%H%M%S)"
BKP_DIR="/var/lib/openclaw/.openclaw-prod/_backup_repo_push/$TS"
remote_mk_backup_dir "$HOST_ALIAS" "$BKP_DIR" >/dev/null
remote_backup_file "$HOST_ALIAS" "$REMOTE_CFG" "$BKP_DIR" "openclaw.json.bak"

echo
echo "== APPLY: writing $REMOTE_CFG (atomic) =="
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$HOST_ALIAS" \
  "sudo -n install -d -m 0700 -o openclaw -g openclaw /var/lib/openclaw/.openclaw-prod"

# write file
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
      exit 20
    fi

    echo
    echo "== AUTO-ROLLBACK: restore previous config =="
    remote_restore_file "$HOST_ALIAS" "$BKP_DIR/openclaw.json.bak" "$REMOTE_CFG" "openclaw:openclaw" "600"
    echo "== Restart openclaw.service (after rollback) =="
    remote_restart_openclaw "$HOST_ALIAS"
    echo "== Healthcheck after rollback =="
    remote_healthcheck "$HOST_ALIAS" || true

    exit 21
  fi
fi

echo "DONE."
