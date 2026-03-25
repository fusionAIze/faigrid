#!/usr/bin/env bash
# ── Projects: git repository management ────────────────────────────────────────
# Sourced by control.sh — all helper functions (_quit, divider, etc.) available.

PROJECTS_DIR="${PROJECTS_DIR:-/opt/faigrid/projects}"

_ensure_projects_dir() {
    [[ -d "$PROJECTS_DIR" ]] && return 0
    mkdir -p "$PROJECTS_DIR" 2>/dev/null \
        || sudo mkdir -p "$PROJECTS_DIR" && sudo chown "$(id -u):$(id -g)" "$PROJECTS_DIR"
}

# Populate caller's project_list array with project directories
_project_arr() {
    local d
    for d in "${PROJECTS_DIR}"/*/; do
        [[ -d "${d}.git" ]] && project_list+=("$d")
    done
}

_projects_print_table() {
    local found=0
    local d
    for d in "${PROJECTS_DIR}"/*/; do
        [[ -d "${d}.git" ]] || continue
        found=1
        local name branch remote commit
        name=$(basename "$d")
        branch=$(git -C "$d" branch --show-current 2>/dev/null || echo "?")
        commit=$(git -C "$d" log -1 --format='%h %s' 2>/dev/null || echo "?")
        remote=$(git -C "$d" remote get-url origin 2>/dev/null \
            | sed 's|https://||;s|git@github.com:||' || echo "?")
        printf "  ${C_BOLD}%-22s${C_RESET}  [${C_CYAN}%s${C_RESET}]  ${C_DIM}%s${C_RESET}\n" \
            "$name" "$branch" "$remote"
        printf "  %-22s  ${C_DIM}%s${C_RESET}\n" "" "$commit"
        echo ""
    done
    [[ "$found" -eq 0 ]] && info "No projects yet — use Clone to add one."
}

_cmd_projects_clone() {
    printf "  ▸ URL or owner/repo  ${C_DIM}(github.com default; prefix gitlab: or bb: for others)${C_RESET}\n"
    read -r -p "  : " repo_input
    [[ -z "$repo_input" ]] && { info "Cancelled."; return; }

    local repo_url
    if echo "$repo_input" | grep -qE "^https?://|^git@"; then
        repo_url="$repo_input"
    else
        case "$repo_input" in
            gitlab:*) repo_url="https://gitlab.com/${repo_input#gitlab:}" ;;
            bb:*|bitbucket:*) repo_url="https://bitbucket.org/${repo_input#*:}" ;;
            *)         repo_url="https://github.com/${repo_input}" ;;
        esac
    fi

    local suggested
    suggested=$(basename "$repo_url" .git)
    printf "  ▸ Local name  [%s]: " "$suggested"
    read -r name_input
    local project_name="${name_input:-$suggested}"

    local dest="${PROJECTS_DIR}/${project_name}"
    if [[ -d "$dest" ]]; then
        warn "Directory ${dest} already exists."; return
    fi
    _ensure_projects_dir
    info "Cloning ${repo_url} → ${dest}…"
    git clone "$repo_url" "$dest"
    success "Project '${project_name}' ready at ${dest}"
}

_cmd_projects_pull() {
    local project_list=()
    _project_arr
    if [[ ${#project_list[@]} -eq 0 ]]; then warn "No projects to update."; return; fi

    local i=1
    printf "  %-4s  %s\n" "No." "PROJECT"
    printf "  %s\n" "──────────────────────"
    for d in "${project_list[@]}"; do
        printf "  ${C_BOLD}%3d)${C_RESET}  %s\n" "$i" "$(basename "$d")"
        i=$((i+1))
    done
    echo ""
    read -r -p "  ▸ Number or all (m = main, q = quit): " choice
    case "$choice" in
        q|Q) _quit ;; m|M|"") return ;;
        all)
            for d in "${project_list[@]}"; do
                info "Pulling $(basename "$d")…"
                git -C "$d" pull || warn "Failed: $(basename "$d")"
            done ;;
        *)
            if [[ "$choice" -ge 1 && "$choice" -le "${#project_list[@]}" ]] 2>/dev/null; then
                local d="${project_list[$((choice-1))]}"
                info "Pulling $(basename "$d")…"
                git -C "$d" pull && success "Done."
            else
                error "Invalid selection."
            fi ;;
    esac
}

_cmd_projects_status() {
    local project_list=()
    _project_arr
    if [[ ${#project_list[@]} -eq 0 ]]; then warn "No projects."; return; fi

    local i=1
    printf "  %-4s  %s\n" "No." "PROJECT"
    printf "  %s\n" "──────────────────────"
    for d in "${project_list[@]}"; do
        printf "  ${C_BOLD}%3d)${C_RESET}  %s\n" "$i" "$(basename "$d")"
        i=$((i+1))
    done
    echo ""
    read -r -p "  ▸ Select (m = main, q = quit): " choice
    case "$choice" in
        q|Q) _quit ;; m|M|"") return ;;
    esac
    if [[ "$choice" -ge 1 && "$choice" -le "${#project_list[@]}" ]] 2>/dev/null; then
        local d="${project_list[$((choice-1))]}"
        echo ""
        divider
        printf "  ${C_BOLD}%s${C_RESET}\n" "$(basename "$d")"
        divider
        git -C "$d" status --short --branch 2>/dev/null
        echo ""
        git -C "$d" log --oneline -10 2>/dev/null
    else
        error "Invalid selection."
    fi
}

_cmd_projects_remove() {
    local project_list=()
    _project_arr
    if [[ ${#project_list[@]} -eq 0 ]]; then warn "No projects."; return; fi

    local i=1
    for d in "${project_list[@]}"; do
        printf "  ${C_BOLD}%3d)${C_RESET}  %s\n" "$i" "$(basename "$d")"
        i=$((i+1))
    done
    echo ""
    read -r -p "  ▸ Select (m = main, q = quit): " choice
    case "$choice" in
        q|Q) _quit ;; m|M|"") return ;;
    esac
    if [[ "$choice" -ge 1 && "$choice" -le "${#project_list[@]}" ]] 2>/dev/null; then
        local d="${project_list[$((choice-1))]}"
        local name; name=$(basename "$d")
        printf "  ${C_RED}⚠${C_RESET}  About to remove ${C_BOLD}%s${C_RESET} (%s)\n" "$name" "$d"
        read -r -p "  Type project name to confirm: " confirm
        if [[ "$confirm" == "$name" ]]; then
            rm -rf "$d"
            success "Project '${name}' removed."
        else
            info "Cancelled."
        fi
    else
        error "Invalid selection."
    fi
}

cmd_projects() {
    while true; do
        wb_header "Projects"
        printf "  ${C_DIM}Git repositories on this node — ${PROJECTS_DIR}${C_RESET}\n\n"
        _projects_print_table
        printf "    ${C_BOLD}1)${C_RESET}  Clone    ${C_DIM}Clone from GitHub / GitLab / Bitbucket${C_RESET}\n"
        printf "    ${C_BOLD}2)${C_RESET}  Pull     ${C_DIM}Update one or all repositories${C_RESET}\n"
        printf "    ${C_BOLD}3)${C_RESET}  Status   ${C_DIM}Branch, log and diff for a project${C_RESET}\n"
        printf "    ${C_BOLD}4)${C_RESET}  Remove   ${C_DIM}Delete a project directory${C_RESET}\n"
        echo ""
        printf "    ${C_BOLD}m)${C_RESET}  Main menu   ${C_BOLD}q)${C_RESET}  Quit\n"
        echo ""
        read -r -p "  ▸ Choice: " opt
        echo ""
        case "$opt" in
            1) _cmd_projects_clone  ;;
            2) _cmd_projects_pull   ;;
            3) _cmd_projects_status ;;
            4) _cmd_projects_remove ;;
            m|M) return ;;
            q|Q) _quit ;;
            *) warn "Invalid option." ;;
        esac
    done
}
