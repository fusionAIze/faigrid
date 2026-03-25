#!/usr/bin/env bash
# ── Skills: cross-agent skill management + source translator ───────────────────
# Sourced by control.sh — all helper functions (_quit, divider, etc.) available.
#
# A "skill" is a SKILL.md file (or equivalent) that instructs an AI agent.
# The translator normalises any source format → SKILL.md content → deploy anywhere.
#
# Supported sources:
#   npx claude-code-templates@latest --skill development/code-reviewer
#   https://raw.githubusercontent.com/org/repo/main/path/SKILL.md
#   /local/path/to/SKILL.md
#   org/repo[/optional/subpath]
#
# Deploy targets (node-local):
#   openclaw    /var/lib/openclaw/.openclaw-prod/skills/<name>/SKILL.md  (sudo)
#   opencode    ~/.config/opencode/skills/<name>/SKILL.md                (user)
#   claude-code ~/.claude/commands/<name>.md                             (user, slash commands)
#
# opencode skill requirements (https://opencode.ai/docs/skills/):
#   - SKILL.md must have YAML frontmatter with 'name' and 'description'
#   - name must match dir name: ^[a-z0-9]+(-[a-z0-9]+)*$  (1-64 chars)
#   - Also reads: ~/.claude/skills/<name>/SKILL.md (claude-compatible path)

SKILLS_REGISTRY="${SKILLS_REGISTRY:-/opt/faigrid/skills}"

# Resolved content and suggested name set by _skill_resolve()
_SKILL_CONTENT=""
_SKILL_NAME_HINT=""

# ── Deploy-path registry ───────────────────────────────────────────────────────
# Prints "agent|mode|path_template" for every known target.
# mode: sudo = requires sudo; user = plain cp as current user
_skill_targets() {
    echo "openclaw|sudo|/var/lib/openclaw/.openclaw-prod/skills/%s/SKILL.md"
    echo "opencode|user|${HOME}/.config/opencode/skills/%s/SKILL.md"
    echo "claude-code|user|${HOME}/.claude/commands/%s.md"
}

# ── opencode frontmatter helpers ──────────────────────────────────────────────
# Returns 0 if SKILL.md already has valid YAML frontmatter (name + description).
_skill_has_frontmatter() {
    local content="$1"
    echo "$content" | head -1 | grep -q "^---" \
        && echo "$content" | grep -q "^name:" \
        && echo "$content" | grep -q "^description:"
}

# Normalise a string to opencode-valid skill name: ^[a-z0-9]+(-[a-z0-9]+)*$
_skill_normalize_name() {
    local raw="$1"
    # lowercase, replace anything not [a-z0-9] with hyphens, collapse runs, strip edges
    echo "$raw" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9]/-/g' \
        | sed 's/--*/-/g' \
        | sed 's/^-//;s/-$//' \
        | cut -c1-64
}

# Prompt user for frontmatter fields and prepend to content.
_skill_add_frontmatter() {
    local skill_name="$1" current_content="$2"
    printf "\n  ${C_YELLOW}opencode${C_RESET} requires YAML frontmatter in SKILL.md.\n"
    printf "  ▸ description: "
    read -r fm_desc
    [[ -z "$fm_desc" ]] && fm_desc="Imported skill"
    local frontmatter
    frontmatter="---
name: ${skill_name}
description: ${fm_desc}
---"
    printf '%s\n\n%s\n' "$frontmatter" "$current_content"
}

_skill_deployed_file() { echo "${SKILLS_REGISTRY}/${1}/.deployed"; }

_skill_is_deployed() {
    local f; f=$(_skill_deployed_file "$1")
    [[ -f "$f" ]] && grep -qF "$2" "$f"
}

_skill_mark_deployed() {
    local f; f=$(_skill_deployed_file "$1")
    mkdir -p "$(dirname "$f")"
    grep -qF "$2" "$f" 2>/dev/null || echo "$2" >> "$f"
}

# ── Translator / resolver ──────────────────────────────────────────────────────
# Sets _SKILL_CONTENT and _SKILL_NAME_HINT; returns 0 on success.

_skill_resolve_npx() {
    local full_cmd="$1"
    # Extract package name (strip version) and --skill path
    local pkg skill_path
    pkg=$(echo "$full_cmd" | sed 's/^npx //;s/@[^ ]*//' | awk '{print $1}')
    skill_path=$(echo "$full_cmd" | grep -oE '\-\-skill ([^ ]+)' | awk '{print $2}')
    _SKILL_NAME_HINT=$(basename "$skill_path" 2>/dev/null || echo "")

    # ── Attempt 1: fetch from known GitHub source ──────────────────────────────
    local github_repo=""
    case "$pkg" in
        claude-code-templates|@anthropic-ai/claude-code-templates)
            github_repo="anthropics/claude-code-templates" ;;
        *)
            # Try npm registry for repository URL
            github_repo=$(npm show "$pkg" repository.url 2>/dev/null \
                | sed 's|git+https://github.com/||;s|\.git$||' || echo "")
            ;;
    esac

    if [[ -n "$github_repo" && -n "$skill_path" ]]; then
        local base="https://raw.githubusercontent.com/${github_repo}/main"
        local candidate content
        for candidate in \
            "${skill_path}/SKILL.md" \
            "templates/${skill_path}/SKILL.md" \
            "skills/${skill_path}/SKILL.md" \
            "${skill_path}.md"; do
            content=$(curl -sf --max-time 10 "${base}/${candidate}" 2>/dev/null || echo "")
            if [[ -n "$content" ]]; then
                _SKILL_CONTENT="$content"
                return 0
            fi
        done
    fi

    # ── Attempt 2: run npx and capture what it installs ───────────────────────
    info "  Trying npx install and capturing output…"
    local cmd_dir="${HOME}/.claude/commands"
    mkdir -p "$cmd_dir"
    local before; before=$(ls "$cmd_dir" 2>/dev/null | sort)
    eval "$full_cmd" >/dev/null 2>&1 || true
    local after; after=$(ls "$cmd_dir" 2>/dev/null | sort)
    local new_file
    new_file=$(comm -13 <(echo "$before") <(echo "$after") | head -1)
    if [[ -n "$new_file" && -f "${cmd_dir}/${new_file}" ]]; then
        _SKILL_CONTENT=$(cat "${cmd_dir}/${new_file}")
        [[ -z "$_SKILL_NAME_HINT" ]] && _SKILL_NAME_HINT="${new_file%.md}"
        return 0
    fi

    warn "Could not resolve skill from npx command."
    return 1
}

_skill_resolve() {
    local src="$1"
    _SKILL_CONTENT=""
    _SKILL_NAME_HINT=""

    # ── npx command ────────────────────────────────────────────────────────────
    if echo "$src" | grep -qE "^npx "; then
        _skill_resolve_npx "$src"
        return

    # ── HTTP/HTTPS URL ─────────────────────────────────────────────────────────
    elif echo "$src" | grep -qE "^https?://"; then
        local c; c=$(curl -sf --max-time 15 "$src" 2>/dev/null || echo "")
        if [[ -z "$c" ]]; then warn "Could not fetch ${src}"; return 1; fi
        _SKILL_CONTENT="$c"
        _SKILL_NAME_HINT=$(basename "$(dirname "$src")")
        return 0

    # ── Local file ─────────────────────────────────────────────────────────────
    elif [[ -f "$src" ]]; then
        _SKILL_CONTENT=$(cat "$src")
        local d; d=$(dirname "$src")
        _SKILL_NAME_HINT=$(basename "$d")
        [[ "$_SKILL_NAME_HINT" == "." ]] && _SKILL_NAME_HINT=$(basename "$src" .md)
        return 0

    # ── GitHub path: owner/repo[/sub/path] ─────────────────────────────────────
    elif echo "$src" | grep -qE "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"; then
        local owner repo subpath=""
        owner=$(echo "$src" | cut -d'/' -f1)
        repo=$(echo "$src"  | cut -d'/' -f2)
        subpath=$(echo "$src" | cut -d'/' -f3-)
        local base="https://raw.githubusercontent.com/${owner}/${repo}/main"
        local c candidate
        for candidate in \
            "${subpath:+${subpath}/SKILL.md}" \
            "${subpath:+${subpath}}" \
            "SKILL.md"; do
            [[ -z "$candidate" ]] && continue
            c=$(curl -sf --max-time 10 "${base}/${candidate}" 2>/dev/null || echo "")
            if [[ -n "$c" ]]; then
                _SKILL_CONTENT="$c"
                _SKILL_NAME_HINT="${subpath:+$(basename "$subpath")}"; _SKILL_NAME_HINT="${_SKILL_NAME_HINT:-$repo}"
                return 0
            fi
        done
        warn "Could not resolve skill from GitHub path: ${src}"; return 1
    fi

    warn "Unrecognised source format. Supported: npx command, URL, file, GitHub owner/repo"
    return 1
}

# ── Deploy to a single agent ───────────────────────────────────────────────────
_skill_deploy_to() {
    local skill_name="$1" agent="$2"
    local skill_src="${SKILLS_REGISTRY}/${skill_name}/SKILL.md"
    [[ -f "$skill_src" ]] || { warn "Skill '${skill_name}' not in registry."; return 1; }

    # opencode: validate name format and ensure frontmatter
    if [[ "$agent" == "opencode" ]]; then
        local valid_name
        valid_name=$(_skill_normalize_name "$skill_name")
        if [[ "$valid_name" != "$skill_name" ]]; then
            warn "Skill name '${skill_name}' is not opencode-compatible (would be '${valid_name}')."
            warn "Rename the skill first or deploy under the normalized name."
            return 1
        fi
        local content; content=$(cat "$skill_src")
        if ! _skill_has_frontmatter "$content"; then
            info "SKILL.md has no frontmatter — opencode requires name + description."
            content=$(_skill_add_frontmatter "$skill_name" "$content")
            # Write frontmatter-enriched copy to a temp file for this deploy
            local tmp; tmp=$(mktemp)
            printf '%s\n' "$content" > "$tmp"
            skill_src="$tmp"
        fi
    fi

    while IFS='|' read -r ag mode path_tpl; do
        [[ "$ag" == "$agent" ]] || continue
        # shellcheck disable=SC2059
        local dest; dest=$(printf "$path_tpl" "$skill_name")
        case "$mode" in
            sudo)
                sudo mkdir -p "$(dirname "$dest")"
                sudo cp "$skill_src" "$dest"
                [[ "$agent" == "openclaw" ]] && \
                    sudo chown -R openclaw:openclaw "$(dirname "$dest")" 2>/dev/null || true
                ;;
            user)
                mkdir -p "$(dirname "$dest")"
                cp "$skill_src" "$dest"
                ;;
        esac
        # Clean up temp file if created
        [[ "$skill_src" == /tmp/* ]] && rm -f "$skill_src"
        _skill_mark_deployed "$skill_name" "$agent"
        success "  Deployed '${skill_name}' → ${agent} (${dest})"
        return 0
    done < <(_skill_targets)

    warn "Unknown agent: ${agent}"
    return 1
}

# ── UI commands ────────────────────────────────────────────────────────────────

_cmd_skills_list() {
    if [[ ! -d "$SKILLS_REGISTRY" ]] || \
       [[ -z "$(ls "$SKILLS_REGISTRY" 2>/dev/null)" ]]; then
        info "No skills in registry. Use Add to import one."
        return
    fi
    printf "\n  %-22s  %s\n" "SKILL" "DEPLOYED TO"
    printf "  %s\n" "──────────────────────────────────────────────────────"
    local d
    for d in "${SKILLS_REGISTRY}"/*/; do
        [[ -f "${d}SKILL.md" ]] || continue
        local name agents=""
        name=$(basename "$d")
        local ag
        while IFS='|' read -r ag _ _; do
            _skill_is_deployed "$name" "$ag" && agents="${agents:+$agents, }${ag}"
        done < <(_skill_targets)
        printf "  ${C_BOLD}%-22s${C_RESET}  ${C_DIM}%s${C_RESET}\n" \
            "$name" "${agents:-(not deployed)}"
    done
    echo ""
}

_cmd_skills_add() {
    wb_header "Add Skill"
    printf "  ${C_DIM}Paste an install command or source — it will be resolved and stored\n"
    printf "  in the local registry, then deployable to any connected agent.${C_RESET}\n\n"
    printf "  ${C_DIM}Examples:\n"
    printf "    npx claude-code-templates@latest --skill development/code-reviewer\n"
    printf "    https://raw.githubusercontent.com/org/repo/main/path/SKILL.md\n"
    printf "    anthropics/claude-code-templates/templates/skills/code-reviewer\n"
    printf "    /opt/faigrid/faigate/skills/faigate/SKILL.md${C_RESET}\n\n"
    read -r -p "  ▸ Source: " source_input
    [[ -z "$source_input" ]] && { info "Cancelled."; return; }

    info "Resolving…"
    if ! _skill_resolve "$source_input"; then
        warn "Could not resolve. Check the source and try again."
        return
    fi

    printf "  ▸ Skill name  [%s]: " "${_SKILL_NAME_HINT:-skill}"
    read -r name_in
    local skill_name
    skill_name=$(_skill_normalize_name "${name_in:-${_SKILL_NAME_HINT:-skill}}")

    local skill_dir="${SKILLS_REGISTRY}/${skill_name}"
    mkdir -p "$skill_dir"
    printf '%s\n' "$_SKILL_CONTENT" > "${skill_dir}/SKILL.md"
    printf '%s\n' "$source_input"   > "${skill_dir}/.source"
    success "Skill '${skill_name}' saved to registry."
    echo ""

    # Preview
    info "── preview (first 5 lines)"
    head -5 "${skill_dir}/SKILL.md" | sed 's/^/  /'
    echo ""

    # Offer deploy
    printf "  Deploy now?\n"
    local ag mode _
    while IFS='|' read -r ag mode _; do
        printf "    → ${C_BOLD}%s${C_RESET}? [y/N]: " "$ag"
        read -r dep_ch
        [[ "${dep_ch:-N}" =~ ^[Yy]$ ]] && _skill_deploy_to "$skill_name" "$ag"
    done < <(_skill_targets)
}

_cmd_skills_deploy() {
    local skills=()
    local d
    for d in "${SKILLS_REGISTRY}"/*/; do
        [[ -f "${d}SKILL.md" ]] && skills+=("$(basename "$d")")
    done
    if [[ ${#skills[@]} -eq 0 ]]; then
        warn "No skills in registry. Use Add first."; return
    fi

    local i=1
    printf "  %-4s  %s\n" "No." "SKILL"
    printf "  %s\n" "──────────────────────"
    local s
    for s in "${skills[@]}"; do
        printf "  ${C_BOLD}%3d)${C_RESET}  %s\n" "$i" "$s"
        i=$((i+1))
    done
    echo ""
    read -r -p "  ▸ Select (m = main, q = quit): " choice
    case "$choice" in
        q|Q) _quit ;; m|M|"") return ;;
    esac
    if ! [[ "$choice" -ge 1 && "$choice" -le "${#skills[@]}" ]] 2>/dev/null; then
        error "Invalid selection."; return
    fi

    local skill_name="${skills[$((choice-1))]}"
    echo ""
    local ag mode _
    while IFS='|' read -r ag mode _; do
        local already=""
        _skill_is_deployed "$skill_name" "$ag" \
            && already=" ${C_DIM}(deployed)${C_RESET}"
        printf "    → ${C_BOLD}%s${C_RESET}%b? [y/N]: " "$ag" "$already"
        read -r dep_ch
        [[ "${dep_ch:-N}" =~ ^[Yy]$ ]] && _skill_deploy_to "$skill_name" "$ag"
    done < <(_skill_targets)
}

cmd_skills() {
    while true; do
        wb_header "Skills"
        printf "  ${C_DIM}Import and deploy AI skills across agents — registry: ${SKILLS_REGISTRY}${C_RESET}\n\n"
        _cmd_skills_list
        printf "    ${C_BOLD}1)${C_RESET}  Add      ${C_DIM}Import from npx / URL / GitHub / local file${C_RESET}\n"
        printf "    ${C_BOLD}2)${C_RESET}  Deploy   ${C_DIM}Deploy a registry skill to one or more agents${C_RESET}\n"
        echo ""
        printf "    ${C_BOLD}m)${C_RESET}  Main menu   ${C_BOLD}q)${C_RESET}  Quit\n"
        echo ""
        read -r -p "  ▸ Choice: " opt
        echo ""
        case "$opt" in
            1) _cmd_skills_add    ;;
            2) _cmd_skills_deploy ;;
            m|M) return ;;
            q|Q) _quit ;;
            *) warn "Invalid option." ;;
        esac
    done
}
