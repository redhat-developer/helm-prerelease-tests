#!/usr/bin/env bash
# Dependency checks: verify static linking per platform.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo ""
echo "=== 03: DEPENDENCIES ==="
echo ""

case "$CURRENT_OS" in
    linux)
        ldd_output="$(ldd "$HELM_BIN" 2>&1)" || true
        if echo "$ldd_output" | grep -qiE "not a dynamic executable|statically linked"; then
            pass "Static linking check (ldd)"
        else
            fail "Static linking check (ldd)" "binary appears dynamically linked: $ldd_output"
        fi
        ;;
    darwin)
        otool_output="$(otool -L "$HELM_BIN" 2>&1)" || true
        lib_count="$(echo "$otool_output" | grep -c "\.dylib\|\.framework" || true)"
        non_system="$(echo "$otool_output" | grep -v "/usr/lib/\|/System/" | grep "\.dylib\|\.framework" || true)"
        if [[ -z "$non_system" ]]; then
            pass "Dependency check — system libs only (${lib_count} libs)"
        else
            fail "Dependency check" "non-system libraries found: $non_system"
        fi
        ;;
    windows)
        skip "Dependency check" "dumpbin not available in CI bash environment"
        ;;
esac

summary
