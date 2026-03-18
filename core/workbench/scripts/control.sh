#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="${HERE}/plugins"

source "${HERE}/_lib.sh"

# Get all valid plugin paths
get_plugins() {
  find "${PLUGINS_DIR}" -type f -name "*.sh" ! -name "_template.sh" | sort
}

# Extracts a variable from a plugin file without sourcing it (safe read)
get_plugin_meta() {
  local plugin_file="$1"
  local var_name="$2"
  grep -E "^${var_name}=" "$plugin_file" | head -n 1 | cut -d'"' -f2 || echo ""
}

cmd_status() {
  print_header "Workbench Registry Status"
  printf "%-15s | %-15s | %-30s | %s\n" "CATEGORY" "TOOL" "DESCRIPTION" "STATUS"
  echo "--------------------------------------------------------------------------------"
  
  while read -r p; do
    local category_name
    category_name=$(get_plugin_meta "$p" "TOOL_CATEGORY")
    local name
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    local desc
    desc=$(get_plugin_meta "$p" "TOOL_DESC")
    
    local stat
    stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
    
    if [[ "$stat" == *"Not installed"* ]]; then
      printf "%-15s | ${C_BOLD}%-15s${C_RESET} | %-30s | ${C_YELLOW}%s${C_RESET}\n" "$category_name" "$name" "$desc" "$stat"
    else
      printf "%-15s | ${C_BOLD}%-15s${C_RESET} | %-30s | ${C_GREEN}%s${C_RESET}\n" "$category_name" "$name" "$desc" "$stat"
    fi
  done < <(get_plugins)
  echo ""
}

cmd_summary() {
  local total=0
  local installed=0
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

cmd_boost() {
  print_header "Boost Workbench — Interactive Selection"
  echo "I will now walk you through each tool category."
  echo "Decide for each if you want to include its tools in this bulk installation."
  echo ""

  # Get unique categories (Bash 3.2 compatible way)
  local categories=()
  while read -r p; do
    local cat
    cat=$(get_plugin_meta "$p" "TOOL_CATEGORY")
    # Add to list if not already there (simple dedup)
    local found=0
    for c in "${categories[@]}"; do
      if [[ "$c" == "$cat" ]]; then found=1; break; fi
    done
    if [[ "$found" -eq 0 ]]; then categories+=("$cat"); fi
  done < <(get_plugins)

  local selected_cats=""
  for cat in "${categories[@]}"; do
    read -r -p "  Include $cat? [y/N]: " include_opt
    if [[ "$include_opt" == "y" || "$include_opt" == "Y" ]]; then
      selected_cats="${selected_cats}${cat} "
    fi
  done

  if [[ -z "$selected_cats" ]]; then
    warn "No categories selected. Boost cancelled."
    return
  fi

  echo ""
  info "Selected for Boost: ${C_BOLD}${selected_cats}${C_RESET}"
  read -r -p "  Confirm and start installation? [Y/n]: " confirm_opt
  if [[ "$confirm_opt" == "n" || "$confirm_opt" == "N" ]]; then
    info "Boost cancelled."
    return
  fi

  echo ""
  for target_cat in $selected_cats; do
    info "Boosting category: $target_cat..."
    while read -r p; do
      local category name
      category=$(get_plugin_meta "$p" "TOOL_CATEGORY")
      name=$(get_plugin_meta "$p" "TOOL_NAME")
      
      if [[ "$category" == "$target_cat" ]]; then
        local stat
        stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
        if [[ "$stat" == *"Not installed"* ]]; then
          printf "  ${C_CYAN}▸${C_RESET} Installing $name...\n"
          (source "$p" && tool_install) >/dev/null 2>&1 || warn "Failed to install $name"
        else
          printf "  ${C_GREEN}✔${C_RESET} $name already installed.\n"
        fi
      fi
    done < <(get_plugins)
    echo ""
  done
  
  success "Boost complete. Run 'status' to review your workbench."
}

cmd_update_all() {
  print_header "Updating All Installed Tools"
  while read -r p; do
    local name
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    local stat
    stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
    
    if [[ "$stat" != *"Not installed"* && "$stat" != "Error" ]]; then
      info "Updating $name..."
      (source "$p" && tool_update) || warn "Failed to update $name"
      success "$name updated."
      echo ""
    fi
  done < <(get_plugins)
}

cmd_install() {
  print_header "Install Tool"

  # Build a plain indexed list (Bash 3.2 compatible — no associative arrays)
  local i=1
  local plugin_list=()
  for p in $(get_plugins); do
    local cat name
    cat=$(get_plugin_meta "$p" "TOOL_CATEGORY")
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    printf "  %2d) [%-10s] %s\n" "$i" "$cat" "$name"
    plugin_list+=("$p")
    i=$((i + 1))
  done

  echo ""
  read -r -p "Select a number to install (or enter to cancel): " choice
  if [[ -z "$choice" ]]; then return; fi

  local idx=$((choice - 1))
  if [[ "$idx" -ge 0 && "$idx" -lt ${#plugin_list[@]} ]]; then
    local p="${plugin_list[$idx]}"
    local name
    name=$(get_plugin_meta "$p" "TOOL_NAME")
    info "Installing $name..."
    (source "$p" && tool_install)
    success "Done. Run 'status' to verify."
  else
    error "Invalid selection."
  fi
}

show_menu() {
  while true; do
    echo -e "${C_CYAN}nexus-core Workbench Control Center${C_RESET}"
    echo "1. View Status / Registry"
    echo "2. Install a Tool"
    echo "3. Update All Installed Tools"
    echo "4. Boost Workbench (Bulk Install)"
    echo "0. Exit"
    echo ""
    read -r -p "Choice: " opt
    echo ""
    
    case "$opt" in
      1) cmd_status ;;
      2) cmd_install ;;
      3) cmd_update_all ;;
      4) cmd_boost ;;
      0|q|quit) exit 0 ;;
      *) warn "Unknown option" ;;
    esac
  done
}

# Run menu if no args, else execute arg
if [[ $# -eq 0 ]]; then
  show_menu
else
  case "$1" in
    status)    cmd_status ;;
    summary)   cmd_summary ;;
    update-all) cmd_update_all ;;
    install)   cmd_install ;;
    boost)     cmd_boost ;;
    *) die "Unknown command: $1" ;;
  esac
fi
