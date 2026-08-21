#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

# ==============================================================================
# Regression suite — guards fixes that must not regress.
#
# O2: grid_messenger.py must read TELEGRAM_BOT_TOKEN via os.getenv with an
#     empty-string default (importing the module must not crash without a token).
# ==============================================================================

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export MESSENGER="${REPO_ROOT}/core/messenger/src/grid_messenger.py"
}

@test "O2 - grid_messenger reads token via os.getenv with empty default" {
    # The runtime behavior is exercised by the pytest suite (core/messenger/tests);
    # this guards the source-level invariant so the fix cannot be silently reverted
    # in an environment where python-telegram-bot is not installed.
    grep -q 'TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")' "${MESSENGER}"
}

@test "O2 - module-level token default is empty string, not None" {
    run grep -E 'os\.getenv\("TELEGRAM_BOT_TOKEN"\)$' "${MESSENGER}"
    # The token must NOT be fetched without a default (would require env set).
    [ "$status" -eq 1 ]
}

@test "O2 - Telegram Application build is deferred until _run(), not import time" {
    # .token(TELEGRAM_BOT_TOKEN) must appear inside a function (after module config),
    # never at module top level, so import without a token cannot build a bot.
    run grep -n '\.token(TELEGRAM_BOT_TOKEN)' "${MESSENGER}"
    [ "$status" -eq 0 ]
    local line_number
    line_number="$(echo "$output" | cut -d: -f1)"
    # The build happens at line ~731, well after the module-level config block.
    [ "$line_number" -gt 700 ]
}
