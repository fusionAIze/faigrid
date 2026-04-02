#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
}

@test "Security Audit - No 'CHANGE_ME' tokens in production scripts" {
    cd "$REPO_ROOT"

    local found_issues
    # Exclude:
    #   - template/example files (*.example, *.template)
    #   - test files and CHANGELOG
    #   - lines where CHANGE_ME appears inside a grep/sed/echo/warn/info call
    #     (these are legitimate sentinel-detection patterns, not hardcoded values)
    found_issues=$(grep -r "CHANGE_ME" . \
        --include="*.sh" \
        --include="*.env" \
        --include="*.yml" \
        --include="*.yaml" \
        --exclude="*.example" \
        --exclude="*.template" \
        --exclude-dir=".git" \
        --exclude-dir="node_modules" \
        --exclude-dir="tests" \
        | grep -v \
            -e 'grep.*CHANGE_ME' \
            -e 'sed.*CHANGE_ME' \
            -e '#.*CHANGE_ME' \
            -e 'echo.*CHANGE_ME' \
            -e 'warn.*CHANGE_ME' \
            -e 'info.*CHANGE_ME' \
            -e '==.*CHANGE_ME' \
            -e '!=.*CHANGE_ME' \
            -e 'CHANGELOG' \
        | cut -d: -f1 | sort -u || echo "")

    if [[ -n "$found_issues" ]]; then
        echo "Found potentially hardcoded CHANGE_ME secrets in:"
        echo "$found_issues"
        return 1
    fi
}

@test "Security Audit - No world-writable scripts" {
    cd "$REPO_ROOT"
    local issues
    issues=$(find . -name "*.sh" -perm -002 -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/.claude/*")
    
    if [[ -n "$issues" ]]; then
        echo "Found world-writable scripts! This is a security risk:"
        echo "$issues"
        return 1
    fi
}

@test "Security Audit - No exposed private keys" {
    cd "$REPO_ROOT"
    
    local found_issues
    found_issues=$(grep -r "BEGIN RSA PRIVATE KEY" . \
        --exclude="*.bats" \
        --exclude-dir=".git" \
        --exclude-dir="tests" \
        --exclude-dir="node_modules" -l || echo "")
        
    if [[ -n "$found_issues" ]]; then
        echo "Potential private key leak detected in:"
        echo "$found_issues"
        return 1
    fi
}
