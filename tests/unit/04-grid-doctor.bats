#!/usr/bin/env bats

load ../.libs/bats-support/load.bash 2>/dev/null || true
load ../.libs/bats-assert/load.bash 2>/dev/null || true

# ==============================================================================
# grid-doctor.sh — free-memory computation and threshold branches
#
# Exercises the REAL _free_mb_darwin / _free_mb_linux / _memory_status
# functions extracted from grid-doctor.sh, driven by stub vm_stat / free
# binaries so the suite runs on any host (no real Darwin/Linux binaries).
# The functions under test are the exact code paths the script executes, not
# reimplementations.
# ==============================================================================

setup() {
    export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

    # Extract the real functions from grid-doctor.sh (never a reimplementation).
    awk '/^_free_mb_darwin\(\)/,/^}/' "${REPO_ROOT}/scripts/grid-doctor.sh" > "${BATS_TEST_TMPDIR}/funcs.sh"
    awk '/^_free_mb_linux\(\)/,/^}/'  "${REPO_ROOT}/scripts/grid-doctor.sh" >> "${BATS_TEST_TMPDIR}/funcs.sh"
    awk '/^_memory_status\(\)/,/^}/'  "${REPO_ROOT}/scripts/grid-doctor.sh" >> "${BATS_TEST_TMPDIR}/funcs.sh"

    # Reporting stubs: capture which branch fires without sourcing _lib.sh.
    cat >> "${BATS_TEST_TMPDIR}/funcs.sh" << 'EOF'
warn() { echo "WARN:$*"; }
success() { echo "SUCCESS:$*"; }
EOF

    # Stub directory on PATH for vm_stat / free.
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    export PATH="${BATS_TEST_TMPDIR}/bin:$PATH"
}

stub_vm_stat() {
    export VM_PAGE_SIZE="$1" VM_FREE_PAGES="$2" VM_INACTIVE_PAGES="$3"
    cat > "${BATS_TEST_TMPDIR}/bin/vm_stat" << 'EOF'
#!/usr/bin/env bash
printf 'Mach Virtual Memory Statistics: (page size of %s bytes)\n' "$VM_PAGE_SIZE"
printf 'Pages free:                              %s.\n' "$VM_FREE_PAGES"
printf 'Pages active:                            %s.\n' "$VM_FREE_PAGES"
printf 'Pages inactive:                          %s.\n' "$VM_INACTIVE_PAGES"
printf 'Pages wired down:                        1000.\n'
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/vm_stat"
}

stub_free() {
    export FREE_MB_STUB="$1"
    cat > "${BATS_TEST_TMPDIR}/bin/free" << 'EOF'
#!/usr/bin/env bash
printf '              total        used        free      shared  buff/cache   available\n'
printf 'Mem:          65536       1234        %s        10        4000       64000\n' "$FREE_MB_STUB"
printf 'Swap:             0           0           0\n'
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/free"
}

@test "Darwin - _free_mb_darwin returns an integer (header page size, not 4096)" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"

    # 1024 free pages at 16384 bytes = 16 MB. A hardcoded 4096 would yield 4.
    stub_vm_stat 16384 1024 0

    run _free_mb_darwin

    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
    [ "$output" -eq 16 ]
}

@test "Linux - _free_mb_linux returns an integer" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"

    stub_free 2048

    run _free_mb_linux

    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
    [ "$output" -eq 2048 ]
}

@test "Darwin - low-memory path fires the warn branch" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"

    # 64 free pages at 16384 bytes = 1 MB -> below the 512 MB threshold.
    stub_vm_stat 16384 64 0

    run _memory_status "$(_free_mb_darwin)"

    [ "$status" -eq 0 ]
    [[ "$output" == WARN:* ]]
    [[ "$output" == *"Low memory detected"* ]]
}

@test "Darwin - sufficient-memory path fires the success branch" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"

    # 65536 free pages at 16384 bytes = 1024 MB -> at/above the threshold.
    stub_vm_stat 16384 65536 0

    run _memory_status "$(_free_mb_darwin)"

    [ "$status" -eq 0 ]
    [[ "$output" == SUCCESS:* ]]
    [[ "$output" == *"Memory:"* ]]
}

@test "Linux - low-memory path fires the warn branch" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"

    stub_free 128

    run _memory_status "$(_free_mb_linux)"

    [ "$status" -eq 0 ]
    [[ "$output" == WARN:* ]]
    [[ "$output" == *"Low memory detected"* ]]
}

@test "Linux - sufficient-memory path fires the success branch" {
    source "${BATS_TEST_TMPDIR}/funcs.sh"

    stub_free 8192

    run _memory_status "$(_free_mb_linux)"

    [ "$status" -eq 0 ]
    [[ "$output" == SUCCESS:* ]]
    [[ "$output" == *"Memory:"* ]]
}
