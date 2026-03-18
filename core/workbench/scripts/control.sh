#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="${HERE}/plugins"

source "${HERE}/_lib.sh"

# Exit cleanly on Ctrl+C / Esc at any point
trap 'printf "\n"; info "Workbench session ended."; exit 0' INT TERM

# ── UI helpers ─────────────────────────────────────────────────────────────────

divider() {
  printf "  %s\n" "──────────────────────────────────────────────────────────────"
}

wb_header() {
  echo ""
  divider
  printf "  ${C_BOLD}%s${C_RESET}\n" "$1"
  divider
  echo ""
}

# ── Plugin helpers ─────────────────────────────────────────────────────────────

get_plugins() {
  find "${PLUGINS_DIR}" -mindepth 2 -type f -name "*.sh" ! -name "_template.sh" | sort
}

# Only plugins without TOOL_MANAGED="auto" — used in install / boost / update
get_installable_plugins() {
  while read -r p; do
    local managed
    managed=$(get_plugin_meta "$p" "TOOL_MANAGED")
    if [[ "$managed" != "auto" ]]; then
      echo "$p"
    fi
  done < <(get_plugins)
}

# Safe metadata read — never sources the plugin
get_plugin_meta() {
  local plugin_file="$1"
  local var_name="$2"
  grep -E "^${var_name}=" "$plugin_file" | head -n 1 | cut -d'"' -f2 || echo ""
}

# Check remote commits behind HEAD using local tracking state (no network call).
# Prints "N commit(s)" if behind, empty string if up-to-date or N/A.
_git_update_check() {
  local dir="$1"
  if [[ ! -d "${dir}/.git" ]]; then echo ""; return; fi
  local behind
  behind=$(git -C "$dir" rev-list HEAD..@{u} --count 2>/dev/null || echo "0")
  if [[ "$behind" -gt 0 ]]; then printf "%s" "${behind} commit(s)"; else echo ""; fi
}

# ── Status ─────────────────────────────────────────────────────────────────────

cmd_status() {
  wb_header "Workbench Registry"
  printf "  %-12s  %-16s  %-28s  %s\n" "CATEGORY" "TOOL" "DESCRIPTION" "STATUS"
  printf "  %s\n" "────────────────────────────────────────────────────────────────────────────"
  while read -r p; do
    local cat name desc stat
    cat=$(get_plugin_meta "$p" "TOOL_CATEGORY")
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    desc=$(get_plugin_meta "$p" "TOOL_DESC")
    stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
    if [[ "$stat" == *"Not installed"* ]]; then
      printf "  %-12s  ${C_BOLD}%-16s${C_RESET}  %-28s  ${C_YELLOW}%s${C_RESET}\n" \
        "$cat" "$name" "$desc" "$stat"
    else
      printf "  %-12s  ${C_BOLD}%-16s${C_RESET}  %-28s  ${C_GREEN}%s${C_RESET}\n" \
        "$cat" "$name" "$desc" "$stat"
    fi
  done < <(get_plugins)
  echo ""
}

cmd_summary() {
  local total=0 installed=0
  while read -r p; do
    total=$((total + 1))
    local stat
    stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
    if [[ "$stat" != *"Not installed"* && "$stat" != "Error" ]]; then
      installed=$((installed + 1))
    fi
  done < <(get_plugins)
  echo "${installed}/${total} tools installed"
}

# ── Install ────────────────────────────────────────────────────────────────────

cmd_install() {
  wb_header "Install Tool"
  local i=1
  local plugin_list=()
  printf "  %-4s  %-12s  %-16s  %s\n" "No." "CATEGORY" "TOOL" "STATUS"
  printf "  %s\n" "──────────────────────────────────────────────────────────"
  while read -r p; do
    local cat name stat
    cat=$(get_plugin_meta "$p" "TOOL_CATEGORY")
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
    if [[ "$stat" == *"Not installed"* ]]; then
      printf "  ${C_BOLD}%3d)${C_RESET}  %-12s  %-16s  ${C_YELLOW}%s${C_RESET}\n" \
        "$i" "$cat" "$name" "$stat"
    else
      printf "  ${C_BOLD}%3d)${C_RESET}  %-12s  %-16s  ${C_GREEN}%s${C_RESET}\n" \
        "$i" "$cat" "$name" "$stat"
    fi
    plugin_list+=("$p")
    i=$((i + 1))
  done < <(get_installable_plugins)

  local total=${#plugin_list[@]}
  echo ""
  read -r -p "  ▸ Select number to install (or q to cancel): " choice
  if [[ -z "$choice" || "$choice" == "q" || "$choice" == "Q" || "$choice" == "0" ]]; then
    info "Install cancelled."
    return
  fi

  if [[ "$choice" -ge 1 && "$choice" -le "$total" ]] 2>/dev/null; then
    local arr_idx=$((choice - 1))
    local p="${plugin_list[$arr_idx]}"
    local name
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    printf "\n  ${C_CYAN}▸${C_RESET}  Installing ${C_BOLD}%s${C_RESET}...\n" "$name"
    (source "$p" && tool_install)
    success "Done. Run Status (1) to verify."
  else
    error "Invalid selection."
  fi
}

# ── Boost: cross-category individual selector ──────────────────────────────────

cmd_boost() {
  wb_header "Boost Workbench — Select Tools"
  printf "  ${C_DIM}Select individual tools for bulk installation across all categories.${C_RESET}\n\n"

  # Build indexed list
  local plugin_list=()
  local i=1
  printf "  %-4s  %-12s  %-16s  %s\n" "No." "CATEGORY" "TOOL" "STATUS"
  printf "  %s\n" "──────────────────────────────────────────────────────────"
  while read -r p; do
    local cat name stat
    cat=$(get_plugin_meta "$p" "TOOL_CATEGORY")
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
    if [[ "$stat" == *"Not installed"* ]]; then
      printf "  ${C_BOLD}%3d)${C_RESET}  %-12s  %-16s  ${C_YELLOW}%s${C_RESET}\n" \
        "$i" "$cat" "$name" "$stat"
    else
      printf "  ${C_BOLD}%3d)${C_RESET}  %-12s  %-16s  ${C_GREEN}%s${C_RESET}\n" \
        "$i" "$cat" "$name" "$stat"
    fi
    plugin_list+=("$p")
    i=$((i + 1))
  done < <(get_installable_plugins)

  local total=${#plugin_list[@]}
  echo ""
  printf "  ${C_BOLD}▸${C_RESET}  Enter numbers (e.g. ${C_BOLD}1 3 5${C_RESET}), "
  printf "${C_BOLD}all${C_RESET} = every not-installed tool, ${C_BOLD}q${C_RESET} = cancel\n\n"
  read -r -p "  Selection: " boost_input

  if [[ -z "$boost_input" || "$boost_input" == "q" || "$boost_input" == "Q" \
        || "$boost_input" == "0" ]]; then
    info "Boost cancelled."
    return
  fi

  # Expand 'all' → indices of not-installed tools
  local selected_indices=""
  if [[ "$boost_input" == "all" ]]; then
    local j=1
    for p in "${plugin_list[@]}"; do
      local stat
      stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
      if [[ "$stat" == *"Not installed"* ]]; then
        selected_indices="$selected_indices $j"
      fi
      j=$((j + 1))
    done
  else
    # Accept space or comma-separated input
    selected_indices="${boost_input//,/ }"
  fi

  if [[ -z "${selected_indices// /}" ]]; then
    warn "Nothing to install."
    return
  fi

  # Confirm list
  echo ""
  printf "  Selected for installation:\n"
  local valid_count=0
  for idx in $selected_indices; do
    if [[ "$idx" -ge 1 && "$idx" -le "$total" ]] 2>/dev/null; then
      local arr_idx=$((idx - 1))
      local n
      n=$(get_plugin_meta "${plugin_list[$arr_idx]}" "TOOL_NAME")
      printf "    ${C_BOLD}·${C_RESET}  %s\n" "$n"
      valid_count=$((valid_count + 1))
    fi
  done

  if [[ "$valid_count" -eq 0 ]]; then
    warn "No valid tools selected."
    return
  fi

  echo ""
  read -r -p "  Confirm and install? [Y/n]: " confirm_opt
  if [[ "$confirm_opt" == "n" || "$confirm_opt" == "N" \
        || "$confirm_opt" == "q" || "$confirm_opt" == "Q" ]]; then
    info "Boost cancelled."
    return
  fi

  echo ""
  for idx in $selected_indices; do
    if [[ "$idx" -ge 1 && "$idx" -le "$total" ]] 2>/dev/null; then
      local arr_idx=$((idx - 1))
      local p="${plugin_list[$arr_idx]}"
      local name stat
      name=$(get_plugin_meta "$p" "TOOL_NAME")
      stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
      if [[ "$stat" == *"Not installed"* ]]; then
        printf "  ${C_CYAN}▸${C_RESET}  Installing ${C_BOLD}%s${C_RESET}...\n" "$name"
        (source "$p" && tool_install) || warn "Failed to install $name"
        printf "  ${C_GREEN}✔${C_RESET}  ${C_BOLD}%s${C_RESET} done.\n\n" "$name"
      else
        printf "  ${C_GREEN}✔${C_RESET}  ${C_BOLD}%s${C_RESET} already installed — skipped.\n" "$name"
      fi
    fi
  done

  echo ""
  success "Boost complete. Run Status (1) to review your workbench."
}

# ── Update: selective with update indicator ─────────────────────────────────────

cmd_update() {
  wb_header "Update Workbench Tools"
  printf "  ${C_DIM}Checking installed tools… (update column uses last-fetched remote state)${C_RESET}\n\n"

  local plugin_list=()
  local installed_indices=""
  local i=1

  printf "  %-4s  %-12s  %-16s  %-24s  %s\n" "No." "CATEGORY" "TOOL" "STATUS" "UPDATE"
  printf "  %s\n" "────────────────────────────────────────────────────────────────────────────"

  while read -r p; do
    local cat name stat install_dir update_label
    cat=$(get_plugin_meta "$p" "TOOL_CATEGORY")
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    install_dir=$(get_plugin_meta "$p" "INSTALL_DIR")
    stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
    plugin_list+=("$p")

    if [[ "$stat" == *"Not installed"* || "$stat" == "Error" ]]; then
      printf "  ${C_BOLD}%3d)${C_RESET}  %-12s  %-16s  ${C_YELLOW}%-24s${C_RESET}  —\n" \
        "$i" "$cat" "$name" "$stat"
    else
      installed_indices="$installed_indices $i"
      # Git-based update check (local tracking branch, no network)
      local behind=""
      if [[ -n "$install_dir" && -d "${install_dir}/.git" ]]; then
        behind=$(_git_update_check "$install_dir")
      fi
      if [[ -n "$behind" ]]; then
        update_label="${C_YELLOW}↑ ${behind}${C_RESET}"
      elif [[ -n "$install_dir" && -d "${install_dir}/.git" ]]; then
        update_label="${C_GREEN}up to date${C_RESET}"
      else
        update_label="${C_DIM}check N/A${C_RESET}"
      fi
      printf "  ${C_BOLD}%3d)${C_RESET}  %-12s  %-16s  ${C_GREEN}%-24s${C_RESET}  " \
        "$i" "$cat" "$name" "$stat"
      printf "%b\n" "$update_label"
    fi
    i=$((i + 1))
  done < <(get_installable_plugins)

  local total=${#plugin_list[@]}

  if [[ -z "${installed_indices// /}" ]]; then
    echo ""
    warn "No tools installed yet. Run Boost (4) to get started."
    return
  fi

  echo ""
  printf "  ${C_BOLD}▸${C_RESET}  Enter numbers (e.g. ${C_BOLD}1 3 5${C_RESET}), "
  printf "${C_BOLD}all${C_RESET} = all installed, ${C_BOLD}q${C_RESET} = cancel\n\n"
  read -r -p "  Selection: " update_input

  if [[ -z "$update_input" || "$update_input" == "q" || "$update_input" == "Q" \
        || "$update_input" == "0" ]]; then
    info "Update cancelled."
    return
  fi

  local selected_indices=""
  if [[ "$update_input" == "all" ]]; then
    selected_indices="$installed_indices"
  else
    selected_indices="${update_input//,/ }"
  fi

  echo ""
  for idx in $selected_indices; do
    if [[ "$idx" -ge 1 && "$idx" -le "$total" ]] 2>/dev/null; then
      local arr_idx=$((idx - 1))
      local p="${plugin_list[$arr_idx]}"
      local name stat
      name=$(get_plugin_meta "$p" "TOOL_NAME")
      stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
      if [[ "$stat" != *"Not installed"* && "$stat" != "Error" ]]; then
        printf "  ${C_CYAN}▸${C_RESET}  Updating ${C_BOLD}%s${C_RESET}...\n" "$name"
        (source "$p" && tool_update) || warn "Failed to update $name"
        printf "  ${C_GREEN}✔${C_RESET}  ${C_BOLD}%s${C_RESET} updated.\n\n" "$name"
      else
        warn "$name is not installed — skipping."
      fi
    else
      warn "Ignoring invalid number: $idx"
    fi
  done

  success "Update run complete."
}

# ── Main menu ──────────────────────────────────────────────────────────────────

show_menu() {
  while true; do
    echo ""
    divider
    printf "  ${C_BOLD}Workbench Control Center${C_RESET}  ${C_DIM}nexus-core${C_RESET}\n"
    divider
    echo ""
    printf "    ${C_BOLD}1)${C_RESET}  ${C_GREEN}Status${C_RESET}       ${C_DIM}Registry overview — installed tools and versions${C_RESET}\n"
    printf "    ${C_BOLD}2)${C_RESET}  Install      ${C_DIM}Install a single tool${C_RESET}\n"
    printf "    ${C_BOLD}3)${C_RESET}  Update       ${C_DIM}Selectively update installed tools${C_RESET}\n"
    printf "    ${C_BOLD}4)${C_RESET}  ${C_CYAN}Boost${C_RESET}        ${C_DIM}Bulk install — pick tools across all categories${C_RESET}\n"
    echo ""
    printf "    ${C_BOLD}q)${C_RESET}  Back / Quit\n"
    echo ""
    read -r -p "  ▸ Choice: " opt
    echo ""
    case "$opt" in
      1) cmd_status ;;
      2) cmd_install ;;
      3) cmd_update ;;
      4) cmd_boost ;;
      0|[qQ]|quit|exit) break ;;
      *) warn "Invalid option — enter 1-4 or q." ;;
    esac
  done
}

# ── Entrypoint ─────────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
  show_menu
else
  case "$1" in
    status)     cmd_status ;;
    summary)    cmd_summary ;;
    update-all) cmd_update ;;
    install)    cmd_install ;;
    boost)      cmd_boost ;;
    *) die "Unknown command: $1" ;;
  esac
fi
