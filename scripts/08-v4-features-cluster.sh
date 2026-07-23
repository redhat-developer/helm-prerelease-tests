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
log_captured "$HELM_BIN install $RELEASE_SSA $CHART_NAME --wait --timeout 5m --debug" "$ssa_output"
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
log_captured "$HELM_BIN install $RELEASE_CSA $CHART_NAME --server-side=false --wait --timeout 5m --debug" "$csa_output"
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
log_captured "$HELM_BIN install $RELEASE_KS $CHART_NAME --wait --timeout 5m" "$ks_output"
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
log_captured "$HELM_BIN upgrade $RELEASE_RBF $CHART_NAME --set image.repository=invalid-image-xxx --rollback-on-failure --wait --timeout 2m" "$rbf_output"
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
log_captured "$HELM_BIN upgrade $RELEASE_ATOMIC $CHART_NAME --set image.repository=invalid-image-xxx --atomic --timeout 2m" "$atomic_output"
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
log_captured "$HELM_BIN upgrade $RELEASE_FR $CHART_NAME --set replicaCount=2 --force-replace --wait --timeout 5m" "$fr_output"
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
log_captured "$HELM_BIN upgrade $RELEASE_FORCE $CHART_NAME --set replicaCount=2 --force --wait --timeout 5m" "$force_output"
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
log_captured "$HELM_BIN push ${OCI_CHART}-0.1.0.tgz oci://${OCI_REPO}" "$push_output"
OCI_DIGEST="$(echo "$push_output" | grep "Digest:" | awk '{print $2}')"

if [[ -n "$OCI_DIGEST" ]]; then
    RELEASE_DIGEST="digest-test-$$"
    digest_install="$("$HELM_BIN" install "$RELEASE_DIGEST" "oci://${OCI_REPO}/${OCI_CHART}@${OCI_DIGEST}" --wait --timeout 5m 2>&1)" || true
    log_captured "$HELM_BIN install $RELEASE_DIGEST oci://${OCI_REPO}/${OCI_CHART}@${OCI_DIGEST} --wait --timeout 5m" "$digest_install"
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
# 10. --atomic on install (v4.2.0+)
# ---------------------------------------------------------------------------
if skip_if_below "--atomic on install" "4.2.0"; then
    RELEASE_INST_ATOMIC="inst-atomic-$$"
    inst_atomic_out="$("$HELM_BIN" install "$RELEASE_INST_ATOMIC" "$CHART_NAME" --atomic --timeout 5m 2>&1)" || true
    log_captured "$HELM_BIN install $RELEASE_INST_ATOMIC $CHART_NAME --atomic --timeout 5m" "$inst_atomic_out"
    if echo "$inst_atomic_out" | grep -qi "STATUS: deployed"; then
        if echo "$inst_atomic_out" | grep -qi "deprecated\|rollback-on-failure"; then
            pass "--atomic on install (deployed with deprecation warning)"
        else
            pass "--atomic on install (deployed)"
        fi
    else
        fail "--atomic on install" "$inst_atomic_out"
    fi
    run_cmd "$HELM_BIN" uninstall "$RELEASE_INST_ATOMIC" || true
fi

# ---------------------------------------------------------------------------
# 11. --dry-run=server respects generateName (v4.2.0+)
# ---------------------------------------------------------------------------
if skip_if_below "--dry-run=server generateName" "4.2.0"; then
    GEN_CHART="v4-genname-test"
    rm -rf "$GEN_CHART"
    run_cmd "$HELM_BIN" create "$GEN_CHART"
    cat > "${GEN_CHART}/templates/genname-cm.yaml" << 'TMPLEOF'
apiVersion: v1
kind: ConfigMap
metadata:
  generateName: gentest-
data:
  key: value
TMPLEOF
    genname_out="$("$HELM_BIN" install genname-test "$GEN_CHART" --dry-run=server 2>&1)" || true
    log_captured "$HELM_BIN install genname-test $GEN_CHART --dry-run=server" "$genname_out"
    if echo "$genname_out" | grep -qi "gentest-"; then
        pass "--dry-run=server generateName"
    else
        fail "--dry-run=server generateName" "$genname_out"
    fi
    rm -rf "$GEN_CHART"
fi

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$CHART_NAME"

summary
