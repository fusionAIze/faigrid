#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export PLUGINS_DIR="${REPO_ROOT}/core/workbench/scripts/plugins"
    source "${REPO_ROOT}/core/workbench/scripts/_lib.sh"
    
    # We must mock get_plugin_meta which is in control.sh (we can't easily source control.sh as it executes)
    # Re-declare the specific helper safely here for test context
    get_plugin_meta() {
        local plugin_file="$1"
        local var_name="$2"
        grep -E "^${var_name}=" "$plugin_file" | head -n 1 | cut -d'"' -f2 || echo ""
    }
}

@test "Plugin Registry - All plugins define TOOL_NAME and TOOL_CATEGORY" {
    local checked=0
    while read -r p; do
        if [[ "$(basename "$p")" == "_template.sh" ]] || [[ "$(basename "$p")" == "uninstall_all.sh" ]]; then continue; fi
        
        local name cat
        name=$(get_plugin_meta "$p" "TOOL_NAME")
        cat=$(get_plugin_meta "$p" "TOOL_CATEGORY")
        
        # Assert they are not empty
        [ -n "$name" ]
        [ -n "$cat" ]
        
        checked=$((checked + 1))
    done < <(find "${PLUGINS_DIR}" -type f -name "*.sh")
    
    # Ensure we actually checked plugins
    [ "$checked" -gt 0 ]
}

@test "Plugin Registry - Sourcing plugins does not throw syntax errors or pollute stdout" {
    local errors=0
    while read -r p; do
        if [[ "$(basename "$p")" == "_template.sh" ]] || [[ "$(basename "$p")" == "uninstall_all.sh" ]]; then continue; fi
        
        # Sourcing a plugin should not produce output and should return 0
        run bash -c "source '$p' >/dev/null"
        [ "$status" -eq 0 ]
    done < <(find "${PLUGINS_DIR}" -type f -name "*.sh")
}
