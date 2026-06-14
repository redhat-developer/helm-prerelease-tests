#!/usr/bin/env bash
# Cluster functionality tests: install, status, upgrade, rollback, uninstall.
# Requires a live Kubernetes cluster (kind, minikube, etc.).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo ""
echo "=== 05: FUNCTIONALITY (CLUSTER) ==="
echo ""

if ! has_cluster; then
    skip_all "no cluster available"
    exit 0
fi

RELEASE_NAME="prerelease-test-$$"
CHART_NAME="cluster-test-chart"

# ---------------------------------------------------------------------------
# Setup: create a local chart for testing
# ---------------------------------------------------------------------------
rm -rf "$CHART_NAME"
"$HELM_BIN" create "$CHART_NAME" &>/dev/null

# ---------------------------------------------------------------------------
# Install chart
# ---------------------------------------------------------------------------
install_output="$("$HELM_BIN" install "$RELEASE_NAME" "$CHART_NAME" --wait --timeout 5m 2>&1)" || true
if echo "$install_output" | grep -qi "STATUS: deployed"; then
    pass "Install chart"
else
    fail "Install chart" "$install_output"
    rm -rf "$CHART_NAME"
    summary
    exit 1
fi

# ---------------------------------------------------------------------------
# Status check
# ---------------------------------------------------------------------------
status_output="$("$HELM_BIN" status "$RELEASE_NAME" 2>&1)" || true
if echo "$status_output" | grep -qi "STATUS: deployed"; then
    pass "Status check"
else
    fail "Status check" "expected deployed status"
fi

# ---------------------------------------------------------------------------
# Upgrade release
# ---------------------------------------------------------------------------
upgrade_output="$("$HELM_BIN" upgrade "$RELEASE_NAME" "$CHART_NAME" --set replicaCount=2 --wait --timeout 5m 2>&1)" || true
list_output="$("$HELM_BIN" list 2>&1)" || true
if echo "$list_output" | grep -q "$RELEASE_NAME" && echo "$list_output" | grep -q "2"; then
    pass "Upgrade release"
else
    fail "Upgrade release" "expected revision 2"
fi

# ---------------------------------------------------------------------------
# Rollback release
# ---------------------------------------------------------------------------
rollback_output="$("$HELM_BIN" rollback "$RELEASE_NAME" 1 --wait --timeout 5m 2>&1)" || true
list_output="$("$HELM_BIN" list 2>&1)" || true
if echo "$list_output" | grep -q "$RELEASE_NAME" && echo "$list_output" | grep -q "3"; then
    pass "Rollback release"
else
    fail "Rollback release" "expected revision 3"
fi

# ---------------------------------------------------------------------------
# Uninstall release
# ---------------------------------------------------------------------------
uninstall_output="$("$HELM_BIN" uninstall "$RELEASE_NAME" 2>&1)" || true
list_output="$("$HELM_BIN" list 2>&1)" || true
if ! echo "$list_output" | grep -q "$RELEASE_NAME"; then
    pass "Uninstall release"
else
    fail "Uninstall release" "release still listed after uninstall"
fi

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$CHART_NAME"

summary
