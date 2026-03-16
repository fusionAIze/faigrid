#!/usr/bin/env bash
# Simple test runner for bash scripts

set -euo pipefail

test_workbench_lib() {
    echo "Running workbench lib tests..."
    # Source the library and check if functions exist
    source "core/workbench/scripts/_lib.sh"
    
    if type info >/dev/null 2>&1; then
        echo "PASS: info() exists"
    else
        echo "FAIL: info() does not exist"
        exit 1
    fi
}

test_control_syntax() {
    echo "Checking control syntax..."
    if bash -n "core/workbench/scripts/control.sh"; then
        echo "PASS: Syntax is ok"
    else
        echo "FAIL: Syntax errors found"
        exit 1
    fi
}

test_security_audit() {
    echo "Running security audit..."
    if bash "tests/security_audit.sh"; then
        echo "PASS: Security audit ok"
    else
        echo "FAIL: Security audit found issues"
        exit 1
    fi
}

echo "Starting tests..."
test_workbench_lib
test_control_syntax
test_security_audit
echo "All tests passed!"
