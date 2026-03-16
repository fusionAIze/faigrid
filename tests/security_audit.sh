#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Nexus Labs - Security Audit Script (Refined)
# ==============================================================================

set -euo pipefail

EXIT_CODE=0

echo "Starting Security Audit..."

# 1. Check for hardcoded secrets or placeholders in example files
check_placeholders() {
    echo "Checking for 'CHANGE_ME' placeholders..."
    # Exclude the test scripts themselves to avoid false positives
    if grep -r "CHANGE_ME" . \
        --exclude="*.example" \
        --exclude="security_audit.sh" \
        --exclude="test_workbench.sh" \
        --exclude-dir=".git" \
        --exclude-dir="node_modules" -l; then
        echo "[WARN] Found 'CHANGE_ME' in non-example files. Ensure these are not active secrets."
    fi
}

# 2. Check for insecure file permissions
check_permissions() {
    echo "Checking for insecure script permissions (writable by others)..."
    # Portably check for group/world writable
    # On macOS, -perm +022 or similar might work, but -perm -002 is specific to "others writable"
    local issues
    issues=$(find . -name "*.sh" -perm -002 -not -path "*/node_modules/*" -not -path "*/.git/*")
    if [[ -n "$issues" ]]; then
        echo "[ERROR] Found world-writable scripts:"
        echo "$issues"
        EXIT_CODE=1
    fi
}

# 3. Check for exposed private keys (basic pattern)
check_keys() {
    echo "Checking for exposed private keys..."
    # Exclude the audit script to avoid matching its own search pattern
    if grep -r "BEGIN RSA PRIVATE KEY" . \
        --exclude="security_audit.sh" \
        --exclude-dir=".git" \
        --exclude-dir="node_modules" -l; then
        echo "[ERROR] Potential private key leak detected!"
        EXIT_CODE=1
    fi
}

check_placeholders
check_permissions
check_keys

if [ $EXIT_CODE -eq 0 ]; then
    echo "Security Audit PASSED."
else
    echo "Security Audit FAILED."
fi

exit $EXIT_CODE
