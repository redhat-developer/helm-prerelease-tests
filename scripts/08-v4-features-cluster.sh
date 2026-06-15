#!/usr/bin/env bash
# v4-specific feature tests requiring a live cluster.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo ""
echo "=== 08: V4 FEATURES (CLUSTER) ==="
echo ""

if ! has_cluster; then
    skip_all "no cluster available"
    exit 0
fi

CHART_NAME="v4-cluster-test"
rm -rf "$CHART_NAME"
run_cmd "$HELM_BIN" create "$CHART_NAME"

# ---------------------------------------------------------------------------
# 1. Server-side apply default
# ---------------------------------------------------------------------------
RELEASE_SSA="ssa-test-$$"
ssa_output="$("$HELM_BIN" install "$RELEASE_SSA" "$CHART_NAME" --wait --timeout 5m --debug 2>&1)" || true
if echo "$ssa_output" | grep -qi "server-side apply"; then
    pass "Server-side apply default"
else
    fail "Server-side apply default" "no SSA debug output found"
fi
run_cmd "$HELM_BIN" uninstall "$RELEASE_SSA" || true

# ---------------------------------------------------------------------------
# 2. Server-side apply override
# ---------------------------------------------------------------------------
RELEASE_CSA="csa-test-$$"
csa_output="$("$HELM_BIN" install "$RELEASE_CSA" "$CHART_NAME" --server-side=false --wait --timeout 5m --debug 2>&1)" || true
if echo "$csa_output" | grep -qi "client-side apply"; then
    pass "Server-side apply override (--server-side=false)"
else
    fail "Server-side apply override" "no client-side apply debug output found"
fi
run_cmd "$HELM_BIN" uninstall "$RELEASE_CSA" || true

# ---------------------------------------------------------------------------
# 3. kstatus watcher
# ---------------------------------------------------------------------------
RELEASE_KS="kstatus-test-$$"
ks_output="$("$HELM_BIN" install "$RELEASE_KS" "$CHART_NAME" --wait --timeout 5m 2>&1)" || true
if echo "$ks_output" | grep -qi "STATUS: deployed"; then
    pass "kstatus watcher (install --wait completes)"
else
    fail "kstatus watcher" "install with --wait did not complete"
fi
run_cmd "$HELM_BIN" uninstall "$RELEASE_KS" || true

# ---------------------------------------------------------------------------
# 4. --rollback-on-failure
# ---------------------------------------------------------------------------
RELEASE_RBF="rbf-test-$$"
run_cmd "$HELM_BIN" install "$RELEASE_RBF" "$CHART_NAME" --wait --timeout 5m || true
rbf_output="$("$HELM_BIN" upgrade "$RELEASE_RBF" "$CHART_NAME" --set image.repository=invalid-image-xxx --rollback-on-failure --wait --timeout 2m 2>&1)" || true
if echo "$rbf_output" | grep -qi "rolled back\|rollback"; then
    pass "--rollback-on-failure"
else
    fail "--rollback-on-failure" "$rbf_output"
fi
run_cmd "$HELM_BIN" uninstall "$RELEASE_RBF" || true

# ---------------------------------------------------------------------------
# 5. Deprecated --atomic
# ---------------------------------------------------------------------------
RELEASE_ATOMIC="atomic-test-$$"
run_cmd "$HELM_BIN" install "$RELEASE_ATOMIC" "$CHART_NAME" --wait --timeout 5m || true
atomic_output="$("$HELM_BIN" upgrade "$RELEASE_ATOMIC" "$CHART_NAME" --set image.repository=invalid-image-xxx --atomic --timeout 2m 2>&1)" || true
if echo "$atomic_output" | grep -qi "deprecated.*rollback-on-failure\|rollback-on-failure.*deprecated"; then
    pass "Deprecated --atomic (warning + rollback)"
elif echo "$atomic_output" | grep -qi "deprecated"; then
    pass "Deprecated --atomic (deprecation warning shown)"
else
    fail "Deprecated --atomic" "$atomic_output"
fi
run_cmd "$HELM_BIN" uninstall "$RELEASE_ATOMIC" || true

# ---------------------------------------------------------------------------
# 6. --force-replace (incompatible with SSA)
# ---------------------------------------------------------------------------
RELEASE_FR="fr-test-$$"
run_cmd "$HELM_BIN" install "$RELEASE_FR" "$CHART_NAME" --server-side=false --wait --timeout 5m || true
fr_output="$("$HELM_BIN" upgrade "$RELEASE_FR" "$CHART_NAME" --set replicaCount=2 --force-replace --wait --timeout 5m 2>&1)" || true
if echo "$fr_output" | grep -qi "STATUS: deployed\|REVISION:"; then
    pass "--force-replace (with --server-side=false)"
else
    fail "--force-replace" "$fr_output"
fi
run_cmd "$HELM_BIN" uninstall "$RELEASE_FR" || true

# ---------------------------------------------------------------------------
# 7. Deprecated --force
# ---------------------------------------------------------------------------
RELEASE_FORCE="force-test-$$"
run_cmd "$HELM_BIN" install "$RELEASE_FORCE" "$CHART_NAME" --server-side=false --wait --timeout 5m || true
force_output="$("$HELM_BIN" upgrade "$RELEASE_FORCE" "$CHART_NAME" --set replicaCount=2 --force --wait --timeout 5m 2>&1)" || true
if echo "$force_output" | grep -qi "deprecated.*force-replace\|force-replace.*deprecated"; then
    pass "Deprecated --force (warning + force-replace)"
elif echo "$force_output" | grep -qi "deprecated"; then
    pass "Deprecated --force (deprecation warning shown)"
else
    fail "Deprecated --force" "$force_output"
fi
run_cmd "$HELM_BIN" uninstall "$RELEASE_FORCE" || true

# ---------------------------------------------------------------------------
# 8. OCI install by digest (cluster required)
# ---------------------------------------------------------------------------
OCI_CHART="v4-digest-test"
OCI_REPO="ttl.sh/helm-v4-digest-$$"
rm -rf "$OCI_CHART" "${OCI_CHART}-0.1.0.tgz"
run_cmd "$HELM_BIN" create "$OCI_CHART"
run_cmd "$HELM_BIN" package "$OCI_CHART"
push_output="$("$HELM_BIN" push "${OCI_CHART}-0.1.0.tgz" "oci://${OCI_REPO}" 2>&1)" || true
OCI_DIGEST="$(echo "$push_output" | grep "Digest:" | awk '{print $2}')"

if [[ -n "$OCI_DIGEST" ]]; then
    RELEASE_DIGEST="digest-test-$$"
    digest_install="$("$HELM_BIN" install "$RELEASE_DIGEST" "oci://${OCI_REPO}/${OCI_CHART}@${OCI_DIGEST}" --wait --timeout 5m 2>&1)" || true
    if echo "$digest_install" | grep -qi "STATUS: deployed"; then
        pass "OCI install by digest"
    else
        fail "OCI install by digest" "$digest_install"
    fi
    run_cmd "$HELM_BIN" uninstall "$RELEASE_DIGEST" || true
else
    fail "OCI install by digest" "push did not return digest"
fi
rm -rf "$OCI_CHART" "${OCI_CHART}-0.1.0.tgz"

# ---------------------------------------------------------------------------
# 9. Color status output
# ---------------------------------------------------------------------------
skip "Color status output" "not verifiable in non-TTY environment — manual check needed"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$CHART_NAME"

summary
