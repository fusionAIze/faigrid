#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="${HERE}/plugins"

source "${HERE}/_lib.sh"

# Ensure user-local bin is on PATH so pipx/rtk installs are visible in subshells
export PATH="${HOME}/.local/bin:${PATH}"

# Exit cleanly on Ctrl+C / Esc at any point
trap '_quit' INT TERM

# Consistent quit: always show rocket banner before exiting.
_quit() {
  echo ""
  divider
  success "fusionAIze Grid Orchestration Complete! 🚀"
  divider
  echo ""
  exit 0
}

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

# Check remote commits behind HEAD — does a git fetch first (network).
# Prints "N commit(s)" if behind, empty string if up-to-date or N/A.
_git_update_check() {
  local dir="$1"
  if [[ ! -d "${dir}/.git" ]]; then echo ""; return; fi
  git -C "$dir" fetch -q 2>/dev/null || true
  local behind
  behind=$(git -C "$dir" rev-list HEAD..@{u} --count 2>/dev/null || echo "0")
  if [[ "$behind" -gt 0 ]]; then printf "%s" "${behind} commit(s)"; else echo ""; fi
}

# npm: compare installed global version against latest published on registry.
# Prints "vX.Y.Z available" or empty string.
_npm_update_check() {
  local pkg="$1"
  local installed latest
  installed=$(npm list -g --depth=0 2>/dev/null \
    | grep -oE "${pkg}@[0-9]+\.[0-9]+\.[0-9]+" | head -1 \
    | cut -d'@' -f2 || echo "")
  [[ -z "$installed" ]] && echo "" && return
  latest=$(npm show "$pkg" version 2>/dev/null || echo "")
  [[ -z "$latest" ]] && echo "" && return
  if [[ "$installed" != "$latest" ]]; then
    printf "v%s available" "$latest"
  fi
}

# github: compare installed version string against latest release tag.
# Prints "vX.Y.Z available" or empty string.
_github_release_check() {
  local repo="$1" installed_ver="$2"
  local latest
  latest=$(curl -sf --max-time 5 \
    "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4 || echo "")
  [[ -z "$latest" ]] && echo "" && return
  # Strip leading 'v' for comparison
  local latest_clean="${latest#v}"
  local installed_clean="${installed_ver#v}"
  if [[ -n "$installed_clean" && "$installed_clean" != "$latest_clean" ]]; then
    printf "%s available" "$latest"
  fi
}

# Dispatcher: reads TOOL_UPDATE_TYPE from plugin metadata and runs the right check.
# Prints update string if update available, empty string if up-to-date or N/A.
_check_update() {
  local plugin_file="$1"
  local update_type install_dir update_pkg update_repo
  update_type=$(get_plugin_meta "$plugin_file" "TOOL_UPDATE_TYPE")
  install_dir=$(get_plugin_meta  "$plugin_file" "INSTALL_DIR")
  update_pkg=$(get_plugin_meta   "$plugin_file" "TOOL_UPDATE_PKG")
  update_repo=$(get_plugin_meta  "$plugin_file" "TOOL_UPDATE_REPO")

  case "$update_type" in
    npm)
      [[ -n "$update_pkg" ]] && _npm_update_check "$update_pkg" || echo ""
      ;;
    git)
      [[ -n "$install_dir" ]] && _git_update_check "$install_dir" || echo ""
      ;;
    github)
      if [[ -n "$update_repo" ]]; then
        # Extract installed version from tool_status output
        local installed_ver
        installed_ver=$( (source "$plugin_file" >/dev/null 2>&1 && tool_status) 2>/dev/null \
          | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
        _github_release_check "$update_repo" "$installed_ver"
      else
        echo ""
      fi
      ;;
    *)
      echo ""
      ;;
  esac
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
  read -r -p "  ▸ Select number to install (c = cancel  q = quit): " choice
  case "$choice" in
    q|Q) _quit ;;
    c|C|""|0) info "Install cancelled."; return ;;
  esac

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
  printf "${C_BOLD}all${C_RESET} = every not-installed tool, ${C_BOLD}c${C_RESET} = cancel, ${C_BOLD}q${C_RESET} = quit\n\n"
  read -r -p "  Selection: " boost_input

  case "$boost_input" in
    q|Q) _quit ;;
    c|C|""|0) info "Boost cancelled."; return ;;
  esac

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
  read -r -p "  Confirm and install? [Y/n/c/q]: " confirm_opt
  case "$confirm_opt" in
    q|Q) _quit ;;
    n|N|c|C) info "Boost cancelled."; return ;;
  esac

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
    local cat name stat update_label
    cat=$(get_plugin_meta "$p" "TOOL_CATEGORY")
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
    plugin_list+=("$p")

    if [[ "$stat" == *"Not installed"* || "$stat" == "Error" ]]; then
      printf "  ${C_BOLD}%3d)${C_RESET}  %-12s  %-16s  ${C_YELLOW}%-24s${C_RESET}  —\n" \
        "$i" "$cat" "$name" "$stat"
    else
      installed_indices="$installed_indices $i"
      local update_info
      update_info=$(_check_update "$p")
      if [[ -n "$update_info" ]]; then
        update_label="${C_YELLOW}↑ ${update_info}${C_RESET}"
      elif [[ -n "$(get_plugin_meta "$p" "TOOL_UPDATE_TYPE")" ]]; then
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
  printf "${C_BOLD}all${C_RESET} = all installed, ${C_BOLD}c${C_RESET} = cancel, ${C_BOLD}q${C_RESET} = quit\n\n"
  read -r -p "  Selection: " update_input

  case "$update_input" in
    q|Q) _quit ;;
    c|C|""|0) info "Update cancelled."; return ;;
  esac

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

# ── Configure ─────────────────────────────────────────────────────────────────

# Check if fusionAIze Gate is installed and return its install dir (or empty)
_faigate_dir() {
  local dir="/opt/faigrid/faigate"
  [[ -d "$dir" ]] && echo "$dir" || echo ""
}

# Show faigate template for a client in dry-run, then offer to write OPENAI env vars
_configure_via_faigate_template() {
  local client="$1" name="$2"
  local faigate_dir
  faigate_dir=$(_faigate_dir)
  local wizard="${faigate_dir}/scripts/faigate-config-wizard"

  echo ""
  printf "  ${C_DIM}Fetching fusionAIze Gate template for ${C_BOLD}%s${C_DIM} (client: %s)…${C_RESET}\n\n" \
    "$name" "$client"

  if [[ -f "$wizard" ]]; then
    bash "$wizard" \
      --client "$client" \
      --purpose general \
      --list-candidates 2>/dev/null || true
    echo ""
    bash "$wizard" \
      --client "$client" \
      --purpose general \
      --dry-run-summary 2>/dev/null || true
  else
    info "Wizard not found at ${wizard} — showing provider list via API instead."
    curl -sf "http://127.0.0.1:8090/api/providers" \
      | python3 -m json.tool 2>/dev/null \
      || warn "fusionAIze Gate not reachable on port 8090."
  fi

  echo ""
  divider
  printf "  ${C_BOLD}Apply faigate routing for %s?${C_RESET}\n" "$name"
  printf "  ${C_DIM}This writes OPENAI_BASE_URL + FAIGATE_CLIENT to grid.env.${C_RESET}\n"
  printf "  ${C_DIM}Your existing tool config is NOT overwritten.${C_RESET}\n\n"
  read -r -p "  ▸ Apply? [y/N]: " apply_choice
  if [[ "${apply_choice:-N}" =~ ^[Yy]$ ]]; then
    (
      source "${HERE}/_lib.sh"
      grid_write_env "OPENAI_BASE_URL" "http://127.0.0.1:8090/v1"
      grid_write_env "OPENAI_API_KEY"  "local"
    )
    success "${name} will route via fusionAIze Gate (OPENAI_BASE_URL=http://127.0.0.1:8090/v1)."
    info "Set ${C_BOLD}X-faigate-Client: ${client}${C_RESET} in ${name}'s request headers for per-client routing."
  else
    info "No changes written."
  fi
}

# Run faigate config wizard scoped to a specific client profile
_configure_faigate_wizard_for_client() {
  local client="$1" name="$2"
  local faigate_dir
  faigate_dir=$(_faigate_dir)
  local wizard="${faigate_dir}/scripts/faigate-config-wizard"
  local config="${faigate_dir}/config.yaml"

  if [[ ! -f "$wizard" ]]; then
    warn "faigate-config-wizard not found. Run git pull in ${faigate_dir}."
    return 1
  fi

  echo ""
  printf "  ${C_DIM}Running fusionAIze Gate Wizard scoped to client profile${C_RESET} ${C_BOLD}%s${C_RESET}\n\n" \
    "$client"

  local purpose
  printf "  Purpose  ${C_DIM}(1=general  2=coding  3=quality  4=free)${C_RESET} [1]: "
  read -r purpose_in
  case "${purpose_in:-1}" in
    2|coding)  purpose="coding"  ;;
    3|quality) purpose="quality" ;;
    4|free)    purpose="free"    ;;
    *)         purpose="general" ;;
  esac

  local cmd_args=("--purpose" "$purpose" "--client" "$client")
  [[ -f "$config" ]] && cmd_args+=(
    "--current-config" "$config" "--merge-existing"
    "--apply" "recommended_add,recommended_replace,recommended_mode_changes"
  )

  echo ""
  printf "  ${C_BOLD}1)${C_RESET}  Dry-run only   ${C_DIM}Preview, no writes${C_RESET}\n"
  printf "  ${C_BOLD}2)${C_RESET}  Write config   ${C_DIM}Update config.yaml with backup${C_RESET}\n"
  read -r -p "  ▸ [1]: " mode_choice
  echo ""

  if [[ "${mode_choice:-1}" == "2" ]]; then
    local bak=".bak-$(date +%Y%m%d%H%M%S)"
    bash "$wizard" "${cmd_args[@]}" --write "$config" --write-backup --backup-suffix "$bak"
    success "config.yaml updated for client '${client}' (backup: ${config}${bak})"
  else
    bash "$wizard" "${cmd_args[@]}" --dry-run-summary
    info "Dry-run complete. Re-run and choose option 2 to apply."
  fi
}

cmd_configure() {
  wb_header "Configure Tool"
  printf "  ${C_DIM}Set API keys and settings. Values persist in${C_RESET} ${C_BOLD}~/.config/faigrid/grid.env${C_RESET}\n\n"

  local plugin_list=()
  local i=1
  local faigate_active
  faigate_active=$(_faigate_dir)
  printf "  %-4s  %-12s  %-16s  %-22s  %s\n" "No." "CATEGORY" "TOOL" "STATUS" "CFG"
  printf "  %s\n" "──────────────────────────────────────────────────────────────────"
  while read -r p; do
    local cat name stat cfg_mark gate_mark
    cat=$(get_plugin_meta  "$p" "TOOL_CATEGORY")
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
    grep -q "^tool_configure()" "$p" 2>/dev/null \
      && cfg_mark="${C_CYAN}✎${C_RESET}" \
      || cfg_mark="${C_DIM}—${C_RESET}"
    # Show Gate indicator if faigate is installed and plugin has FAIGATE_CLIENT
    if [[ -n "$faigate_active" ]]; then
      local fc
      fc=$(get_plugin_meta "$p" "FAIGATE_CLIENT")
      [[ -n "$fc" ]] && gate_mark=" ${C_MAGENTA}⊕${C_RESET}" || gate_mark=""
    else
      gate_mark=""
    fi
    if [[ "$stat" == *"Not installed"* || "$stat" == "Error" ]]; then
      printf "  ${C_BOLD}%3d)${C_RESET}  %-12s  %-16s  ${C_YELLOW}%-22s${C_RESET}  %b%b\n" \
        "$i" "$cat" "$name" "$stat" "$cfg_mark" "$gate_mark"
    else
      printf "  ${C_BOLD}%3d)${C_RESET}  %-12s  %-16s  ${C_GREEN}%-22s${C_RESET}  %b%b\n" \
        "$i" "$cat" "$name" "$stat" "$cfg_mark" "$gate_mark"
    fi
    plugin_list+=("$p")
    i=$((i + 1))
  done < <(get_plugins)

  local total=${#plugin_list[@]}
  echo ""
  printf "  ${C_DIM}✎ = interactive config   ⊕ = fusionAIze Gate template available${C_RESET}\n\n"
  printf "  ${C_BOLD}▸${C_RESET}  Select tool to configure (c = cancel  q = quit)\n\n"
  read -r -p "  Selection: " choice

  case "$choice" in
    q|Q) _quit ;;
    c|C|""|0) info "Configure cancelled."; return ;;
  esac

  if [[ "$choice" -ge 1 && "$choice" -le "$total" ]] 2>/dev/null; then
    local arr_idx=$((choice - 1))
    local p="${plugin_list[$arr_idx]}"
    local name faigate_client
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    faigate_client=$(get_plugin_meta "$p" "FAIGATE_CLIENT")

    echo ""
    divider
    printf "  ${C_BOLD}Configuring: %s${C_RESET}\n" "$name"
    divider
    echo ""

    # ── 3-way choice when Gate is installed and plugin has a client profile ──
    local configure_mode="direct"
    if [[ -n "$faigate_active" && -n "$faigate_client" ]]; then
      printf "  ${C_MAGENTA}fusionAIze Gate${C_RESET} is active and has a template for ${C_BOLD}%s${C_RESET}.\n\n" \
        "$name"
      printf "  ${C_BOLD}1)${C_RESET}  ${C_MAGENTA}Gate Template${C_RESET}    ${C_DIM}Preview faigate routing template — apply without overwriting tool config${C_RESET}\n"
      printf "  ${C_BOLD}2)${C_RESET}  ${C_CYAN}Gate Wizard${C_RESET}      ${C_DIM}Run faigate config wizard scoped to this client profile${C_RESET}\n"
      printf "  ${C_BOLD}3)${C_RESET}  Tool Config      ${C_DIM}Configure %s directly (tool's own settings)${C_RESET}\n" "$name"
      echo ""
      read -r -p "  ▸ Choice [3]: " route_choice
      echo ""
      case "${route_choice:-3}" in
        1) configure_mode="gate-template" ;;
        2) configure_mode="gate-wizard"   ;;
        *) configure_mode="direct"        ;;
      esac
    fi

    case "$configure_mode" in
      "gate-template")
        _configure_via_faigate_template "$faigate_client" "$name"
        ;;
      "gate-wizard")
        _configure_faigate_wizard_for_client "$faigate_client" "$name"
        ;;
      "direct")
        (
          source "${HERE}/_lib.sh"
          source "$p"
          if declare -f tool_configure >/dev/null 2>&1; then
            tool_configure
          else
            info "No interactive configuration available for ${name}."
            info "Check the tool's own documentation for setup options."
          fi
        ) || warn "Configuration of ${name} encountered an error."
        ;;
    esac

    echo ""
    ( source "${HERE}/_lib.sh" && grid_ensure_sourced ) 2>/dev/null || true
  else
    error "Invalid selection."
  fi
}

# ── Uninstall ─────────────────────────────────────────────────────────────────

cmd_uninstall() {
  wb_header "Uninstall Tool"
  printf "  ${C_DIM}Only installed tools are shown. This cannot be undone.${C_RESET}\n\n"

  local plugin_list=()
  local i=1
  printf "  %-4s  %-12s  %-16s  %s\n" "No." "CATEGORY" "TOOL" "STATUS"
  printf "  %s\n" "──────────────────────────────────────────────────────────"

  while read -r p; do
    local cat name stat
    cat=$(get_plugin_meta "$p" "TOOL_CATEGORY")
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
    if [[ "$stat" != *"Not installed"* && "$stat" != "Error" ]]; then
      printf "  ${C_BOLD}%3d)${C_RESET}  %-12s  %-16s  ${C_GREEN}%s${C_RESET}\n" \
        "$i" "$cat" "$name" "$stat"
      plugin_list+=("$p")
      i=$((i + 1))
    fi
  done < <(get_plugins)

  if [[ ${#plugin_list[@]} -eq 0 ]]; then
    echo ""
    warn "No tools installed."
    return
  fi

  local total=${#plugin_list[@]}
  echo ""
  read -r -p "  ▸ Select number to uninstall (c = cancel  q = quit): " choice
  case "$choice" in
    q|Q) _quit ;;
    c|C|""|0) info "Uninstall cancelled."; return ;;
  esac

  if [[ "$choice" -ge 1 && "$choice" -le "$total" ]] 2>/dev/null; then
    local arr_idx=$((choice - 1))
    local p="${plugin_list[$arr_idx]}"
    local name
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    echo ""
    printf "  ${C_RED}⚠${C_RESET}  You are about to uninstall ${C_BOLD}%s${C_RESET}.\n" "$name"
    read -r -p "  Type the tool name to confirm, or press Enter to cancel: " confirm
    if [[ "$confirm" != "$name" ]]; then
      info "Uninstall cancelled."
      return
    fi
    printf "\n  ${C_CYAN}▸${C_RESET}  Uninstalling ${C_BOLD}%s${C_RESET}...\n" "$name"
    (source "$p" && tool_uninstall) || warn "Uninstall of $name encountered an error."
    success "Done. Run Status (1) to verify."
  else
    error "Invalid selection."
  fi
}

# ── Service Control ────────────────────────────────────────────────────────────

# Determine if a service is Running or Stopped.
_ctrl_service_status() {
  local tool_type="$1" service="$2"
  case "$tool_type" in
    systemd)
      systemctl is-active --quiet "${service}.service" 2>/dev/null \
        && echo "Running" || echo "Stopped"
      ;;
    docker)
      docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${service}$" \
        && echo "Running" || echo "Stopped"
      ;;
    *)
      # git-type tools (e.g. faigate): systemd-first, docker-fallback
      if systemctl is-active --quiet "${service}.service" 2>/dev/null; then
        echo "Running"
      elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${service}"; then
        echo "Running"
      else
        echo "Stopped"
      fi
      ;;
  esac
}

# Execute start/stop/restart/logs for a service.
_ctrl_action() {
  local action="$1" tool_type="$2" service="$3"
  case "$tool_type" in
    systemd) _ctrl_systemd "$action" "$service" ;;
    docker)  _ctrl_docker  "$action" "$service" ;;
    *)
      # git-type: prefer systemd if the unit exists
      if systemctl list-units --full --all 2>/dev/null \
           | grep -q "${service}.service"; then
        _ctrl_systemd "$action" "$service"
      else
        _ctrl_docker "$action" "$service"
      fi ;;
  esac
}

_ctrl_systemd() {
  local action="$1" service="$2"
  case "$action" in
    start)   sudo systemctl start   "${service}.service" \
               && success "${service} started."   ;;
    stop)    sudo systemctl stop    "${service}.service" \
               && success "${service} stopped."   ;;
    restart) sudo systemctl restart "${service}.service" \
               && success "${service} restarted." ;;
    logs)    sudo journalctl -u "${service}.service" -n 50 --no-pager ;;
  esac
}

_ctrl_docker() {
  local action="$1" service="$2"
  case "$action" in
    start)   docker start   "$service" && success "${service} started."   ;;
    stop)    docker stop    "$service" && success "${service} stopped."   ;;
    restart) docker restart "$service" && success "${service} restarted." ;;
    logs)    docker logs --tail 50 "$service" ;;
  esac
}

cmd_control() {
  wb_header "Service Control"
  printf "  ${C_DIM}Start, stop, restart or tail logs for installed services.${C_RESET}\n\n"

  local plugin_list=()
  local i=1

  printf "  %-4s  %-12s  %-16s  %-8s  %s\n" "No." "CATEGORY" "TOOL" "TYPE" "STATUS"
  printf "  %s\n" "──────────────────────────────────────────────────────────────"

  while read -r p; do
    local cat name tool_type tool_service inst_stat svc_stat
    cat=$(get_plugin_meta  "$p" "TOOL_CATEGORY")
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    tool_type=$(get_plugin_meta "$p" "TOOL_TYPE")
    tool_service=$(get_plugin_meta "$p" "TOOL_SERVICE")
    [[ -z "$tool_service" ]] && tool_service="$name"

    # Only services we can actually control
    [[ "$tool_type" != "systemd" && "$tool_type" != "docker" \
       && "$tool_type" != "git" ]] && continue

    # Only installed tools
    inst_stat=$( (source "$p" >/dev/null 2>&1 && tool_status) 2>/dev/null || echo "" )
    [[ "$inst_stat" == *"Not installed"* || -z "$inst_stat" ]] && continue

    svc_stat=$(_ctrl_service_status "$tool_type" "$tool_service")

    local color="$C_RED"
    [[ "$svc_stat" == "Running" ]] && color="$C_GREEN"

    printf "  ${C_BOLD}%3d)${C_RESET}  %-12s  %-16s  %-8s  ${color}%s${C_RESET}\n" \
      "$i" "$cat" "$name" "$tool_type" "$svc_stat"
    plugin_list+=("$p")
    i=$((i + 1))
  done < <(get_plugins)

  if [[ ${#plugin_list[@]} -eq 0 ]]; then
    echo ""; warn "No controllable services found."; return
  fi

  local total=${#plugin_list[@]}
  echo ""
  read -r -p "  ▸ Select service (c = cancel  q = quit): " choice
  case "$choice" in
    q|Q) _quit ;;
    c|C|"") info "Cancelled."; return ;;
  esac

  if ! [[ "$choice" -ge 1 && "$choice" -le "$total" ]] 2>/dev/null; then
    error "Invalid selection."; return
  fi

  local p="${plugin_list[$((choice - 1))]}"
  local name tool_type tool_service
  name=$(get_plugin_meta        "$p" "TOOL_NAME")
  tool_type=$(get_plugin_meta   "$p" "TOOL_TYPE")
  tool_service=$(get_plugin_meta "$p" "TOOL_SERVICE")
  [[ -z "$tool_service" ]] && tool_service="$name"

  local cur_stat color
  cur_stat=$(_ctrl_service_status "$tool_type" "$tool_service")
  color="$C_RED"; [[ "$cur_stat" == "Running" ]] && color="$C_GREEN"

  echo ""
  printf "  ${C_BOLD}%s${C_RESET}  ${C_DIM}(%s)${C_RESET}  Status: ${color}%s${C_RESET}\n\n" \
    "$name" "$tool_service" "$cur_stat"
  printf "    ${C_BOLD}1)${C_RESET}  Start\n"
  printf "    ${C_BOLD}2)${C_RESET}  Stop\n"
  printf "    ${C_BOLD}3)${C_RESET}  Restart\n"
  printf "    ${C_BOLD}4)${C_RESET}  Logs     ${C_DIM}last 50 lines${C_RESET}\n"
  echo ""
  read -r -p "  ▸ Action (c = cancel): " action
  echo ""

  case "$action" in
    q|Q)    _quit ;;
    c|C|"") info "Cancelled."; return ;;
    1) _ctrl_action "start"   "$tool_type" "$tool_service" ;;
    2) _ctrl_action "stop"    "$tool_type" "$tool_service" ;;
    3) _ctrl_action "restart" "$tool_type" "$tool_service" ;;
    4) _ctrl_action "logs"    "$tool_type" "$tool_service" ;;
    *) error "Invalid action." ;;
  esac
}

# ── Doctor / Validate ─────────────────────────────────────────────────────────

cmd_doctor() {
  wb_header "Doctor / Validate"
  printf "  ${C_DIM}Run health checks and diagnostics for installed tools.${C_RESET}\n\n"

  local plugin_list=()
  local i=1
  printf "  %-4s  %-12s  %-16s  %s\n" "No." "CATEGORY" "TOOL" "STATUS"
  printf "  %s\n" "──────────────────────────────────────────────────────────"

  while read -r p; do
    grep -q "^tool_doctor()" "$p" 2>/dev/null || continue
    local cat name stat
    cat=$(get_plugin_meta  "$p" "TOOL_CATEGORY")
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
    [[ "$stat" == *"Not installed"* || "$stat" == "Error" ]] && continue
    printf "  ${C_BOLD}%3d)${C_RESET}  %-12s  %-16s  ${C_GREEN}%s${C_RESET}\n" \
      "$i" "$cat" "$name" "$stat"
    plugin_list+=("$p")
    i=$((i + 1))
  done < <(get_plugins)

  if [[ ${#plugin_list[@]} -eq 0 ]]; then
    echo ""
    warn "No tools with doctor/validate support are currently installed."
    return
  fi

  local total=${#plugin_list[@]}
  echo ""
  read -r -p "  ▸ Select tool (c = cancel  q = quit): " choice
  case "$choice" in
    q|Q) _quit ;;
    c|C|"") info "Cancelled."; return ;;
  esac

  if [[ "$choice" -ge 1 && "$choice" -le "$total" ]] 2>/dev/null; then
    local arr_idx=$((choice - 1))
    local p="${plugin_list[$arr_idx]}"
    local name
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    echo ""
    divider
    printf "  ${C_BOLD}Doctor: %s${C_RESET}\n" "$name"
    divider
    echo ""
    (
      source "${HERE}/_lib.sh"
      source "$p"
      tool_doctor
    ) || warn "Doctor run for ${name} completed with warnings."
  else
    error "Invalid selection."
  fi
}

# ── Main menu ──────────────────────────────────────────────────────────────────

show_menu() {
  while true; do
    echo ""
    divider
    printf "  ${C_BOLD}Workbench Control Center${C_RESET}  ${C_DIM}grid-core${C_RESET}\n"
    divider
    echo ""
    printf "    ${C_BOLD}1)${C_RESET}  ${C_GREEN}Status${C_RESET}       ${C_DIM}Registry overview — installed tools and versions${C_RESET}\n"
    printf "    ${C_BOLD}2)${C_RESET}  Install      ${C_DIM}Install a single tool${C_RESET}\n"
    printf "    ${C_BOLD}3)${C_RESET}  Update       ${C_DIM}Selectively update installed tools${C_RESET}\n"
    printf "    ${C_BOLD}4)${C_RESET}  ${C_CYAN}Boost${C_RESET}        ${C_DIM}Bulk install — pick tools across all categories${C_RESET}\n"
    printf "    ${C_BOLD}5)${C_RESET}  ${C_MAGENTA}Configure${C_RESET}    ${C_DIM}Set API keys and tool settings${C_RESET}\n"
    printf "    ${C_BOLD}6)${C_RESET}  ${C_RED}Uninstall${C_RESET}    ${C_DIM}Remove an installed tool${C_RESET}\n"
    printf "    ${C_BOLD}7)${C_RESET}  ${C_CYAN}Control${C_RESET}      ${C_DIM}Start, stop, restart or tail logs for a service${C_RESET}\n"
    printf "    ${C_BOLD}8)${C_RESET}  ${C_YELLOW}Doctor${C_RESET}       ${C_DIM}Health checks and diagnostics for installed tools${C_RESET}\n"
    echo ""
    printf "    ${C_BOLD}q)${C_RESET}  Quit\n"
    echo ""
    read -r -p "  ▸ Choice: " opt
    echo ""
    case "$opt" in
      1) cmd_status ;;
      2) cmd_install ;;
      3) cmd_update ;;
      4) cmd_boost ;;
      5) cmd_configure ;;
      6) cmd_uninstall ;;
      7) cmd_control ;;
      8) cmd_doctor ;;
      0|[qQ]|quit|exit) _quit ;;
      *) warn "Invalid option — enter 1-8 or q." ;;
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
    configure)  cmd_configure ;;
    uninstall)  cmd_uninstall ;;
    control)    cmd_control ;;
    doctor)     cmd_doctor ;;
    *) die "Unknown command: $1" ;;
  esac
fi
