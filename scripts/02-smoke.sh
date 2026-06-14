#!/usr/bin/env bash
# Smoke tests: version, Go version, help output, environment info.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo ""
echo "=== 02: SMOKE TESTS ==="
echo ""

# ---------------------------------------------------------------------------
# Version check
# ---------------------------------------------------------------------------
version_output="$("$HELM_BIN" version --short 2>&1)" || true
if echo "$version_output" | grep -q "v${HELM_VERSION}"; then
    pass "Version check (${version_output})"
else
    fail "Version check" "expected v${HELM_VERSION}, got: $version_output"
fi

# ---------------------------------------------------------------------------
# Go version — Red Hat build
# ---------------------------------------------------------------------------
full_version="$("$HELM_BIN" version 2>&1)" || true
if echo "$full_version" | grep -q "Red Hat"; then
    go_ver="$(echo "$full_version" | grep -oE 'go[0-9]+\.[0-9]+\.[0-9]+ \(Red Hat [^)]+\)' || echo "found")"
    pass "Go version — Red Hat build (${go_ver})"
else
    fail "Go version — Red Hat build" "expected 'Red Hat' in: $full_version"
fi

# ---------------------------------------------------------------------------
# Help output
# ---------------------------------------------------------------------------
help_output="$("$HELM_BIN" help 2>&1)" || true
if echo "$help_output" | grep -qi "kubernetes package manager"; then
    pass "Help command"
else
    fail "Help command" "expected 'Kubernetes package manager' in help output"
fi

# ---------------------------------------------------------------------------
# Environment info
# ---------------------------------------------------------------------------
env_output="$("$HELM_BIN" env 2>&1)" || true
if echo "$env_output" | grep -q "HELM_"; then
    pass "Environment info"
else
    fail "Environment info" "expected HELM_ variables in env output"
fi

summary
