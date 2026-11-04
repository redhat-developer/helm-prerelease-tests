#!/usr/bin/env bash
# Shared library for helm binary prerelease tests.
# Sourced by each test script — not executed directly.

set -uo pipefail

# ---------------------------------------------------------------------------
# Verbose mode — set VERBOSE=1 to see all command output
# ---------------------------------------------------------------------------
VERBOSE="${VERBOSE:-0}"

run_cmd() {
    if [[ "$VERBOSE" == "1" ]]; then
        echo "  \$ $*"
        "$@" 2>&1 | sed 's/^/  | /'
        return "${PIPESTATUS[0]}"
    else
        "$@" &>/dev/null
    fi
}

log_verbose() {
    if [[ "$VERBOSE" == "1" ]]; then
        echo "  $*"
    fi
}

# ---------------------------------------------------------------------------
# Capture helper — like run_cmd but stores output in LAST_OUTPUT for checks.
# Usage: run_capture "$HELM_BIN" install ... ; echo "$LAST_OUTPUT"
# ---------------------------------------------------------------------------
LAST_OUTPUT=""
run_capture() {
    log_verbose "\$ $*"
    LAST_OUTPUT="$("$@" 2>&1)" || true
    if [[ "$VERBOSE" == "1" ]] && [[ -n "$LAST_OUTPUT" ]]; then
        echo "$LAST_OUTPUT" | sed 's/^/  | /'
    fi
}

# Show a captured variable in verbose mode (command label + output).
log_captured() {
    local label="$1"
    local output="$2"
    log_verbose "\$ $label"
    if [[ "$VERBOSE" == "1" ]] && [[ -n "$output" ]]; then
        echo "$output" | sed 's/^/  | /'
    fi
}

# ---------------------------------------------------------------------------
# Test counters
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAILURES=()

pass() {
    local name="$1"
    echo "PASS: ${name}"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    local name="$1"
    local detail="${2:-}"
    if [[ -n "$detail" ]]; then
        echo "FAIL: ${name} — ${detail}"
    else
        echo "FAIL: ${name}"
    fi
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILURES+=("$name")
}

skip() {
    local name="$1"
    local reason="${2:-}"
    if [[ -n "$reason" ]]; then
        echo "SKIP: ${name} — ${reason}"
    else
        echo "SKIP: ${name}"
    fi
    SKIP_COUNT=$((SKIP_COUNT + 1))
}

# ---------------------------------------------------------------------------
# A skip that is only legitimate in some environments.
#
# A plain skip() does not touch FAIL_COUNT, so a suite whose checks all
# skip still exits 0 and reports green. That is correct where skipping is
# meaningful (no Go toolchain on the macOS runners) and actively wrong
# where it is not: on a FIPS-enabled guest, a skipped FIPS assertion means
# the one thing the guest exists to prove was never proven, and the green
# tick certifies nothing.
#
# Pass mandatory=1 to turn a skip into a failure. Where a check is
# mandatory, a passing suite is itself evidence that the check ran -- no
# log archaeology required, which matters because CI prunes logs long
# before anyone goes looking.
#
# Usage: skip_or_fail <mandatory 0|1> <name> <reason>
# ---------------------------------------------------------------------------
skip_or_fail() {
    local mandatory="$1" name="$2" reason="${3:-}"
    if [[ "$mandatory" == "1" ]]; then
        fail "$name" "required in this environment but did not run: ${reason}"
    else
        skip "$name" "$reason"
    fi
}

# Whole-suite skip (e.g. no cluster available). Counts as one reported
# result so the zero-result guard in summary() does not mistake a
# legitimate suite-wide skip for a suite that never ran.
skip_all() {
    local reason="$1"
    echo "SKIP ALL: ${reason}"
    SKIP_COUNT=$((SKIP_COUNT + 1))
}

summary() {
    local total=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
    echo ""
    echo "==========================================="
    echo "TOTAL: ${total}  PASS: ${PASS_COUNT}  FAIL: ${FAIL_COUNT}  SKIP: ${SKIP_COUNT}"
    if [[ ${#FAILURES[@]} -gt 0 ]]; then
        echo "FAILURES:"
        for f in "${FAILURES[@]}"; do
            echo "  - ${f}"
        done
    fi
    echo "==========================================="
    # A suite that reported nothing has not passed -- it has not run.
    # Guards against a script exiting early or every check vanishing,
    # both of which otherwise look identical to success.
    if [[ $total -eq 0 ]]; then
        echo "ERROR: no checks reported a result -- treating as failure"
        return 1
    fi
    [[ $FAIL_COUNT -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Version comparison
# ---------------------------------------------------------------------------
version_gte() {
    local current="$1" required="$2"
    current="${current#v}"
    required="${required#v}"
    printf '%s\n%s\n' "$required" "$current" | sort -V | head -n1 | grep -qx "$required"
}

skip_if_below() {
    local name="$1" min_version="$2"
    if ! version_gte "$HELM_VERSION" "$min_version"; then
        skip "$name" "requires helm >= ${min_version}, have ${HELM_VERSION}"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------
if [[ -n "${HELM_PLATFORM:-}" ]]; then
    CURRENT_OS="${HELM_PLATFORM%%-*}"
    GOARCH="${HELM_PLATFORM#*-}"
    PLATFORM="$HELM_PLATFORM"
else
    CURRENT_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    CURRENT_ARCH="$(uname -m)"

    case "$CURRENT_OS" in
        mingw*|msys*|cygwin*) CURRENT_OS="windows" ;;
    esac

    case "$CURRENT_ARCH" in
        x86_64)  GOARCH="amd64" ;;
        aarch64) GOARCH="arm64" ;;
        arm64)   GOARCH="arm64" ;;
        ppc64le) GOARCH="ppc64le" ;;
        s390x)   GOARCH="s390x" ;;
        *)       GOARCH="$CURRENT_ARCH" ;;
    esac

    PLATFORM="${CURRENT_OS}-${GOARCH}"
fi

# ---------------------------------------------------------------------------
# Binary path
# ---------------------------------------------------------------------------
if [[ -z "${HELM_BIN:-}" ]]; then
    if [[ "$CURRENT_OS" == "windows" ]]; then
        HELM_BIN="./helm-${PLATFORM}.exe"
    else
        HELM_BIN="./helm-${PLATFORM}"
    fi
fi

if [[ ! -x "$HELM_BIN" ]] && [[ -f "$HELM_BIN" ]]; then
    chmod +x "$HELM_BIN"
fi

# ---------------------------------------------------------------------------
# Helm version
# ---------------------------------------------------------------------------
if [[ -x "$HELM_BIN" ]] || [[ -f "$HELM_BIN" ]]; then
    HELM_VERSION="$("$HELM_BIN" version --short 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")"
else
    HELM_VERSION="${HELM_VERSION:-unknown}"
fi

# ---------------------------------------------------------------------------
# Tool detection
# ---------------------------------------------------------------------------
case "$CURRENT_OS" in
    linux)
        CHECKSUM_CMD="sha256sum"
        DEP_CHECK_CMD="ldd"
        ;;
    darwin)
        CHECKSUM_CMD="shasum -a 256"
        DEP_CHECK_CMD="otool -L"
        ;;
    windows)
        CHECKSUM_CMD="certutil -hashfile"
        DEP_CHECK_CMD=""
        ;;
esac

if command -v podman &>/dev/null; then
    CONTAINER_RUNTIME="podman"
elif command -v docker &>/dev/null; then
    CONTAINER_RUNTIME="docker"
else
    CONTAINER_RUNTIME=""
fi

# ---------------------------------------------------------------------------
# Helm home isolation
# ---------------------------------------------------------------------------
HELM_TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/helm-test-home.XXXXXX")"
export HELM_CONFIG_HOME="${HELM_TEST_HOME}/config"
export HELM_CACHE_HOME="${HELM_TEST_HOME}/cache"
export HELM_DATA_HOME="${HELM_TEST_HOME}/data"
mkdir -p "$HELM_CONFIG_HOME" "$HELM_CACHE_HOME" "$HELM_DATA_HOME"

cleanup_helm_home() {
    if [[ -d "${HELM_TEST_HOME:-}" ]]; then
        rm -rf "$HELM_TEST_HOME"
    fi
}
trap cleanup_helm_home EXIT

# ---------------------------------------------------------------------------
# macOS Gatekeeper
# ---------------------------------------------------------------------------
if [[ "$CURRENT_OS" == "darwin" ]] && [[ -f "$HELM_BIN" ]]; then
    xattr -d com.apple.quarantine "$HELM_BIN" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Cluster detection
# ---------------------------------------------------------------------------
has_cluster() {
    kubectl cluster-info &>/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Script directory (for sourcing from any working dir)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "--- Platform: ${PLATFORM} | Helm: ${HELM_VERSION} | Binary: ${HELM_BIN} | Verbose: ${VERBOSE} ---"
