#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

# ==============================================================================
# _skills.sh — npx dispatch without unquoted expansion (C9)
#
# The npx fallback path previously ran `command $full_cmd`, i.e. unquoted
# expansion of operator input: word-splitting and glob expansion applied. The
# fix tokenises the command line into an array and invokes `command "${args[@]}"`
# so each element is a single argument.
#
# These tests extract the REAL _skill_tokenize / _skill_resolve_npx functions
# (never a reimplementation), stub the resolver's network/`command` surface,
# and prove that arguments containing a space or a glob `*` survive as single
# arguments: no word-splitting, no pathname expansion.
# ==============================================================================

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    local skills="${REPO_ROOT}/core/workbench/scripts/_skills.sh"

    # Extract the real dispatch code from _skills.sh (never a reimplementation).
    awk '/^_skill_tokenize\(\)/,/^}/'             "$skills" > "${BATS_TEST_TMPDIR}/funcs.sh"
    awk '/^_skill_resolve_npx\(\)/,/^}/'          "$skills" >> "${BATS_TEST_TMPDIR}/funcs.sh"

    # Reporting stubs: _skill_resolve_npx calls info/warn on its normal path.
    cat >> "${BATS_TEST_TMPDIR}/funcs.sh" << 'EOF'
info() { :; }
warn() { :; }
EOF

    # Sandbox where the resolver looks for freshly installed commands, and a
    # standalone stub bin dir we prepend to PATH to capture npx argv.
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    export PATH="${BATS_TEST_TMPDIR}/bin:$PATH"
}

# Stub `command` so npx does not run for real: the fake npx below records its
# argv, proving what reaches the command line. `command -v` (used implicitly by
# the `command` builtin to locate npx) resolves the fake npx on PATH.
stub_npx() {
    export NX_ARGS_FILE="${BATS_TEST_TMPDIR}/npx_args"
    : > "$NX_ARGS_FILE"
    cat > "${BATS_TEST_TMPDIR}/bin/npx" << 'EOF'
#!/usr/bin/env bash
for a in "$@"; do
    printf '%s\n' "$a" >> "$NX_ARGS_FILE"
done
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/npx"
}

npx_argc() { wc -l < "${BATS_TEST_TMPDIR}/npx_args" | tr -d ' '; }
npx_arg()  { sed -n "$1p" "${BATS_TEST_TMPDIR}/npx_args"; }

# ── _skill_tokenize unit assertions ──────────────────────────────────────────

@test "tokenize: quoted space stays a single word" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"

    run _skill_tokenize 'npx pkg --skill "my skill"'

    [ "$status" -eq 0 ]
    [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 4 ]
    [ "$(echo "$output" | sed -n '4p')" = "my skill" ]
}

@test "tokenize: glob character is not expanded" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"

    run _skill_tokenize 'npx pkg --skill "foo*bar"'

    [ "$status" -eq 0 ]
    [ "$(echo "$output" | sed -n '4p')" = "foo*bar" ]
}

# ── dispatch assertions: argv reaches the command as single arguments ────────

@test "dispatch: space-containing arg survives as a single argument" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"
    stub_npx

    # mkdir so the resolver's ls/comm plumbing runs cleanly.
    mkdir -p "${HOME}/.claude/commands" 2>/dev/null || true

    run _skill_resolve_npx 'npx pkg --skill "my skill"'

    # `command npx ...` runs the fake npx with $0=npx, so argv = pkg --skill "my skill".
    [ "$(npx_argc)" -eq 3 ]
    [ "$(npx_arg 1)" = "pkg" ]
    [ "$(npx_arg 2)" = "--skill" ]
    [ "$(npx_arg 3)" = "my skill" ]
}

@test "dispatch: glob-containing arg survives without pathname expansion" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"
    stub_npx

    mkdir -p "${HOME}/.claude/commands" 2>/dev/null || true

    run _skill_resolve_npx 'npx pkg --skill "foo*bar"'

    [ "$(npx_argc)" -eq 3 ]
    [ "$(npx_arg 1)" = "pkg" ]
    [ "$(npx_arg 2)" = "--skill" ]
    [ "$(npx_arg 3)" = "foo*bar" ]
}
