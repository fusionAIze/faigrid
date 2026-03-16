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
  
  for p in $(get_plugins); do
    local cat=$(get_plugin_meta "$p" "TOOL_CATEGORY")
    local name=$(get_plugin_meta "$p" "TOOL_NAME")
    local desc=$(get_plugin_meta "$p" "TOOL_DESC")
    
    local stat
    stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
    
    if [[ "$stat" == *"Not installed"* ]]; then
      printf "%-15s | ${C_BOLD}%-15s${C_RESET} | %-30s | ${C_YELLOW}%s${C_RESET}\n" "$cat" "$name" "$desc" "$stat"
    else
      printf "%-15s | ${C_BOLD}%-15s${C_RESET} | %-30s | ${C_GREEN}%s${C_RESET}\n" "$cat" "$name" "$desc" "$stat"
    fi
  done
  echo ""
}

cmd_update_all() {
  print_header "Updating All Installed Tools"
  for p in $(get_plugins); do
    local name=$(get_plugin_meta "$p" "TOOL_NAME")
    local stat=$( (source "$p" >/dev/null 2>&1 && tool_status) || echo "Error" )
    
    if [[ "$stat" != *"Not installed"* && "$stat" != "Error" ]]; then
      info "Updating $name..."
      (source "$p" && tool_update) || warn "Failed to update $name"
      success "$name updated."
      echo ""
    fi
  done
}

cmd_install() {
  print_header "Install Tool"
  
  # Give a quick list
  local i=1
  declare -A plugin_map
  for p in $(get_plugins); do
    local cat=$(get_plugin_meta "$p" "TOOL_CATEGORY")
    local name=$(get_plugin_meta "$p" "TOOL_NAME")
    printf "  %2d) [%-10s] %s\n" "$i" "$cat" "$name"
    plugin_map[$i]="$p"
    ((i++))
  done
  
  echo ""
  read -r -p "Select a number to install (or enter to cancel): " choice
  if [[ -z "$choice" ]]; then return; fi
  
  if [[ -n "${plugin_map[$choice]:-}" ]]; then
    local p="${plugin_map[$choice]}"
    local name=$(get_plugin_meta "$p" "TOOL_NAME")
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
    echo "0. Exit"
    echo ""
    read -r -p "Choice: " opt
    echo ""
    
    case "$opt" in
      1) cmd_status ;;
      2) cmd_install ;;
      3) cmd_update_all ;;
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
    update-all) cmd_update_all ;;
    install)   cmd_install ;;
    *) die "Unknown command: $1" ;;
  esac
fi
