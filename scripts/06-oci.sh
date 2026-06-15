#!/usr/bin/env bash
# OCI operations: push to ttl.sh, install from OCI, install by digest.
# Push works without a cluster. Install requires a live cluster.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo ""
echo "=== 06: OCI OPERATIONS ==="
echo ""

CHART_NAME="oci-test-chart"
OCI_REPO="ttl.sh/helm-prerelease-$$"

rm -rf "$CHART_NAME" "${CHART_NAME}-0.1.0.tgz"
run_cmd "$HELM_BIN" create "$CHART_NAME"
run_cmd "$HELM_BIN" package "$CHART_NAME"

# ---------------------------------------------------------------------------
# Push chart to OCI
# ---------------------------------------------------------------------------
push_output="$("$HELM_BIN" push "${CHART_NAME}-0.1.0.tgz" "oci://${OCI_REPO}" 2>&1)" || true
if echo "$push_output" | grep -q "Pushed:" && echo "$push_output" | grep -q "Digest:"; then
    OCI_DIGEST="$(echo "$push_output" | grep "Digest:" | awk '{print $2}')"
    pass "Push chart to OCI"
else
    fail "Push chart to OCI" "$push_output"
    rm -rf "$CHART_NAME" "${CHART_NAME}-0.1.0.tgz"
    summary
    exit 1
fi

# ---------------------------------------------------------------------------
# Install from OCI (cluster required)
# ---------------------------------------------------------------------------
if has_cluster; then
    RELEASE_OCI="oci-install-$$"
    install_output="$("$HELM_BIN" install "$RELEASE_OCI" "oci://${OCI_REPO}/${CHART_NAME}" --version 0.1.0 --wait --timeout 5m 2>&1)" || true
    if echo "$install_output" | grep -qi "STATUS: deployed"; then
        pass "Install from OCI"
    else
        fail "Install from OCI" "$install_output"
    fi
    run_cmd "$HELM_BIN" uninstall "$RELEASE_OCI" || true
else
    skip "Install from OCI" "no cluster available"
fi

# ---------------------------------------------------------------------------
# Install by digest (cluster required)
# ---------------------------------------------------------------------------
if has_cluster; then
    RELEASE_DIGEST="oci-digest-$$"
    install_output="$("$HELM_BIN" install "$RELEASE_DIGEST" "oci://${OCI_REPO}/${CHART_NAME}@${OCI_DIGEST}" --wait --timeout 5m 2>&1)" || true
    if echo "$install_output" | grep -qi "STATUS: deployed"; then
        pass "Install from OCI by digest"
    else
        fail "Install from OCI by digest" "$install_output"
    fi
    run_cmd "$HELM_BIN" uninstall "$RELEASE_DIGEST" || true
else
    skip "Install from OCI by digest" "no cluster available"
fi

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$CHART_NAME" "${CHART_NAME}-0.1.0.tgz"

summary
