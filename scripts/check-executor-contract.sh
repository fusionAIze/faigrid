#!/usr/bin/env bash
# Executor Contract conformance check
# ─────────────────────────────────────────────────────────────────────────────
# Enumerates the Workbench plugins (mirroring control.sh get_plugins) and
# reports, per plugin, which pieces of the Executor Contract v1 checklist are
# mechanically greppable:
#   * TOOL_* metadata (TOOL_NAME / TOOL_CATEGORY / TOOL_DESC / TOOL_TYPE)
#   * lifecycle functions (tool_install / tool_status / tool_uninstall)
#   * the optional tool_configure / tool_doctor / tool_update
#   * "Not installed" literal in tool_status (the registry's install marker)
#
# The JSON status emitter is a v1 *target* (see the doc's migration note), so
# it is reported as a separate, non-blocking column. A plugin that passes all
# REQUIRED checks is CONFORMANT; a plugin missing only target-JSON is reported
# CONFORMANT with a "json=no" note.
#
# Exit codes: by default this script REPORTS and exits 0 (the fleet is not yet
# green — see addendum V9). Use --strict to exit non-zero when any plugin is
# non-conformant. Use --json to emit a JSONL verdict per plugin.
#
# See docs/reference/executor-contract.md (authoritative).
set -euo pipefail

PLUGINS_DIR="core/workbench/scripts/plugins"

STRICT=0
AS_JSON=0
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1 ;;
    --json)   AS_JSON=1 ;;
    --help|-h)
      echo "usage: $0 [--strict] [--json]" >&2
      echo "  --strict  exit non-zero if any plugin is non-conformant" >&2
      echo "  --json    emit one JSON verdict object per plugin" >&2
      exit 0
      ;;
    *)
      echo "$0: unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

# Quote a value for use as the "message" field of the verdict JSON.
_json_escape() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | tr -d '\000-\037'
}

# Emit an aligned report row. Columns are tab-delimited.
report_row() {
  printf '%-42s %-10s  %s\n' "$1" "$2" "$3"
}

nonconformant=0
checked=0
json_emitted=0

# Left/right align headers to match report_row's printf widths.
if [[ "$AS_JSON" -eq 0 ]]; then
  report_row "PLUGIN" "VERDICT" "NOTES"
  report_row "------" "-------" "-----"
fi

while IFS= read -r plugin; do
  [[ -n "$plugin" ]] || continue
  checked=$((checked + 1))
  missing=""

  # Required metadata (doc: "Metadata (TOOL_*)").
  for var in TOOL_NAME TOOL_CATEGORY TOOL_DESC TOOL_TYPE; do
    grep -qE "^${var}=" "$plugin" || missing="${missing} ${var}"
  done

  # Required lifecycle functions.
  for fn in tool_install tool_status tool_uninstall; do
    grep -qE "^${fn}\(\)" "$plugin" || missing="${missing} ${fn}()"
  done

  # Optional functions, reported for completeness only.
  optional=""
  for fn in tool_configure tool_doctor tool_update; do
    if grep -qE "^${fn}\(\)" "$plugin"; then
      optional="${optional} ${fn}()"
    fi
  done

  # "Not installed" literal (doc: tool_status MUST print exactly this when absent).
  notinst=no
  if grep -qE 'echo[[:space:]]+"Not installed"' "$plugin" \
     || grep -qE '"[Nn]ot installed"' "$plugin"; then
    notinst=yes
  fi

  # Target JSON emitter — a v1 target, not required (migration note).
  json=no
  if grep -qE '\{"status":"|\{ "status":"' "$plugin"; then
    json=yes
    json_emitted=$((json_emitted + 1))
  fi

  if [[ -z "$missing" ]]; then
    verdict="CONFORMANT"
  else
    verdict="NONCONFORMANT"
    nonconformant=$((nonconformant + 1))
  fi

  notes=""
  [[ "$notinst" == "yes" ]] && notes="notinst=yes" || notes="notinst=no"
  notes="${notes} json=${json}"
  notes="${notes} opt:[${optional# }]"
  [[ -n "$missing" ]] && notes="${notes} missing:[${missing# }]"

  if [[ "$AS_JSON" -eq 1 ]]; then
    printf '{"plugin":"%s","conformant":%s,"missing":"%s","not_installed_literal":%s,"json_emitter":%s}\n' \
      "$(_json_escape "$(basename "$plugin")")" \
      "$([[ "$verdict" == "CONFORMANT" ]] && echo "true" || echo "false")" \
      "$(_json_escape "${missing# }")" \
      "$([[ "$notinst" == "yes" ]] && echo "true" || echo "false")" \
      "$([[ "$json" == "yes" ]] && echo "true" || echo "false")"
  else
    report_row "$(basename "$plugin")" "$verdict" "$notes"
  fi
done < <(find "$PLUGINS_DIR" -mindepth 2 -type f -name "*.sh" ! -name "_template.sh" | sort)

if [[ "$AS_JSON" -eq 0 ]]; then
  echo ""
  echo "Plugins checked: ${checked}"
  echo "Conformant:      $((checked - nonconformant))"
  echo "Nonconformant:   ${nonconformant}"
  echo "JSON emitters:   ${json_emitted} (target, not required)"
fi

if [[ "$STRICT" -eq 1 && "$nonconformant" -gt 0 ]]; then
  echo "STRICT MODE: ${nonconformant} non-conformant plugin(s)." >&2
  exit 1
fi

exit 0
