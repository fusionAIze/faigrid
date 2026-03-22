#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
}

@test "Security Audit - No 'CHANGE_ME' tokens in production scripts" {
    cd "$REPO_ROOT"
    
    local found_issues
    # We ignore standard test files, example configs, node_modules.
    found_issues=$(grep -r "CHANGE_ME" . \
        --exclude="*.example" \
        --exclude="*.template" \
        --exclude="*.bats" \
        --exclude-dir=".git" \
        --exclude-dir="node_modules" \
        --exclude-dir="tests" -l || echo "")
        
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
