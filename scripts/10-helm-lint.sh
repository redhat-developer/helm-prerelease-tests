#!/usr/bin/env bash
# Comprehensive helm lint tests: semver validation, strict mode, values, errors.
# Note: scripts/04-functionality-offline.sh covers the basic helm lint smoke test.
# This script provides comprehensive lint coverage (flags, semver variants, error detection).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo ""
echo "=== 10: HELM LINT ==="
echo ""

# ---------------------------------------------------------------------------
# Lint a valid chart (baseline)
# ---------------------------------------------------------------------------
rm -rf lint-valid-chart
run_cmd "$HELM_BIN" create lint-valid-chart
if [[ -d lint-valid-chart ]]; then
    lint_output="$("$HELM_BIN" lint lint-valid-chart 2>&1)" || true
    log_captured "$HELM_BIN lint lint-valid-chart" "$lint_output"
    if echo "$lint_output" | grep -q "1 chart(s) linted, 0 chart(s) failed"; then
        pass "Lint valid chart"
    else
        fail "Lint valid chart" "$lint_output"
    fi
else
    fail "Lint valid chart" "helm create failed to create chart directory"
fi
rm -rf lint-valid-chart

# ---------------------------------------------------------------------------
# Lint with --strict (warnings treated as errors)
# ---------------------------------------------------------------------------
rm -rf lint-strict-chart
run_cmd "$HELM_BIN" create lint-strict-chart
if [[ -d lint-strict-chart ]]; then
    # Remove the description field to trigger a "description is empty" lint warning
    grep -v "^description:" lint-strict-chart/Chart.yaml > lint-strict-chart/Chart.yaml.tmp
    mv lint-strict-chart/Chart.yaml.tmp lint-strict-chart/Chart.yaml
    strict_output="$("$HELM_BIN" lint lint-strict-chart --strict 2>&1)" || true
    log_captured "$HELM_BIN lint lint-strict-chart --strict" "$strict_output"
    if echo "$strict_output" | grep -q "1 chart(s) failed"; then
        pass "Lint --strict (warnings treated as errors)"
    else
        fail "Lint --strict" "expected chart failure with --strict on chart missing description: $strict_output"
    fi
else
    fail "Lint --strict" "helm create failed to create chart directory"
fi
rm -rf lint-strict-chart

# ---------------------------------------------------------------------------
# Lint chart with valid semver version
# ---------------------------------------------------------------------------
rm -rf lint-semver-valid
run_cmd "$HELM_BIN" create lint-semver-valid
if [[ -d lint-semver-valid ]]; then
    cat > lint-semver-valid/Chart.yaml << 'CHARTEOF'
apiVersion: v2
name: lint-semver-valid
description: Chart with valid semver version
type: application
version: 1.2.3
appVersion: "1.0.0"
CHARTEOF
    semver_output="$("$HELM_BIN" lint lint-semver-valid 2>&1)" || true
    log_captured "$HELM_BIN lint lint-semver-valid" "$semver_output"
    if echo "$semver_output" | grep -q "0 chart(s) failed"; then
        pass "Lint valid semver version (1.2.3)"
    else
        fail "Lint valid semver version" "$semver_output"
    fi
else
    fail "Lint valid semver version" "helm create failed to create chart directory"
fi
rm -rf lint-semver-valid

# ---------------------------------------------------------------------------
# Lint chart with invalid semver version
# ---------------------------------------------------------------------------
rm -rf lint-semver-invalid
run_cmd "$HELM_BIN" create lint-semver-invalid
if [[ -d lint-semver-invalid ]]; then
    cat > lint-semver-invalid/Chart.yaml << 'CHARTEOF'
apiVersion: v2
name: lint-semver-invalid
description: Chart with invalid semver version
type: application
version: not-a-version
appVersion: "1.0.0"
CHARTEOF
    invalid_output="$("$HELM_BIN" lint lint-semver-invalid 2>&1)" || true
    log_captured "$HELM_BIN lint lint-semver-invalid" "$invalid_output"
    if echo "$invalid_output" | grep -q "1 chart(s) failed"; then
        pass "Lint invalid semver version detected"
    else
        fail "Lint invalid semver version" "expected chart failure for invalid version 'not-a-version': $invalid_output"
    fi
else
    fail "Lint invalid semver version" "helm create failed to create chart directory"
fi
rm -rf lint-semver-invalid

# ---------------------------------------------------------------------------
# Lint chart with missing patch component in version (1.0 — semver boundary)
# ---------------------------------------------------------------------------
# The Masterminds/semver library used by Helm coerces "1.0" to "1.0.0" and
# emits a lint WARNING rather than an ERROR, so bare "helm lint" may report
# "0 chart(s) failed".  --strict promotes that WARNING to an ERROR, ensuring
# a two-part version string is always caught as a chart failure.
rm -rf lint-semver-nopatch
run_cmd "$HELM_BIN" create lint-semver-nopatch
if [[ -d lint-semver-nopatch ]]; then
    cat > lint-semver-nopatch/Chart.yaml << 'CHARTEOF'
apiVersion: v2
name: lint-semver-nopatch
description: Chart with missing patch component in semver
type: application
version: 1.0
appVersion: "1.0.0"
CHARTEOF
    nopatch_output="$("$HELM_BIN" lint lint-semver-nopatch --strict 2>&1)" || true
    log_captured "$HELM_BIN lint lint-semver-nopatch --strict" "$nopatch_output"
    if echo "$nopatch_output" | grep -q "1 chart(s) failed"; then
        pass "Lint rejects missing-patch version (1.0)"
    else
        fail "Lint rejects missing-patch version" "expected chart failure for version '1.0' with --strict: $nopatch_output"
    fi
else
    fail "Lint rejects missing-patch version" "helm create failed to create chart directory"
fi
rm -rf lint-semver-nopatch

# ---------------------------------------------------------------------------
# Lint chart with prerelease semver version
# ---------------------------------------------------------------------------
rm -rf lint-semver-prerelease
run_cmd "$HELM_BIN" create lint-semver-prerelease
if [[ -d lint-semver-prerelease ]]; then
    cat > lint-semver-prerelease/Chart.yaml << 'CHARTEOF'
apiVersion: v2
name: lint-semver-prerelease
description: Chart with prerelease semver version
type: application
version: 1.0.0-alpha.1
appVersion: "1.0.0"
CHARTEOF
    prerelease_output="$("$HELM_BIN" lint lint-semver-prerelease 2>&1)" || true
    log_captured "$HELM_BIN lint lint-semver-prerelease" "$prerelease_output"
    if echo "$prerelease_output" | grep -q "0 chart(s) failed"; then
        pass "Lint prerelease semver (1.0.0-alpha.1)"
    else
        fail "Lint prerelease semver" "$prerelease_output"
    fi
else
    fail "Lint prerelease semver" "helm create failed to create chart directory"
fi
rm -rf lint-semver-prerelease

# ---------------------------------------------------------------------------
# Lint chart with build metadata semver version
# ---------------------------------------------------------------------------
rm -rf lint-semver-build
run_cmd "$HELM_BIN" create lint-semver-build
if [[ -d lint-semver-build ]]; then
    cat > lint-semver-build/Chart.yaml << 'CHARTEOF'
apiVersion: v2
name: lint-semver-build
description: Chart with build metadata semver version
type: application
version: 2.0.0+build.42
appVersion: "2.0.0"
CHARTEOF
    build_output="$("$HELM_BIN" lint lint-semver-build 2>&1)" || true
    log_captured "$HELM_BIN lint lint-semver-build" "$build_output"
    if echo "$build_output" | grep -q "0 chart(s) failed"; then
        pass "Lint build metadata semver (2.0.0+build.42)"
    else
        fail "Lint build metadata semver" "$build_output"
    fi
else
    fail "Lint build metadata semver" "helm create failed to create chart directory"
fi
rm -rf lint-semver-build

# ---------------------------------------------------------------------------
# Lint with external values file (--values)
# ---------------------------------------------------------------------------
rm -rf lint-values-chart
run_cmd "$HELM_BIN" create lint-values-chart
if [[ -d lint-values-chart ]]; then
    cat > lint-extra-values.yaml << 'VALEOF'
replicaCount: 3
image:
  tag: "test-values"
VALEOF
    values_output="$("$HELM_BIN" lint lint-values-chart --values lint-extra-values.yaml 2>&1)" || true
    log_captured "$HELM_BIN lint lint-values-chart --values lint-extra-values.yaml" "$values_output"
    if echo "$values_output" | grep -q "0 chart(s) failed"; then
        pass "Lint with --values file"
    else
        fail "Lint with --values file" "$values_output"
    fi
    rm -f lint-extra-values.yaml
else
    fail "Lint with --values file" "helm create failed to create chart directory"
fi
rm -rf lint-values-chart

# ---------------------------------------------------------------------------
# Lint with --set overrides
# ---------------------------------------------------------------------------
rm -rf lint-set-chart
run_cmd "$HELM_BIN" create lint-set-chart
if [[ -d lint-set-chart ]]; then
    set_output="$("$HELM_BIN" lint lint-set-chart --set replicaCount=5 2>&1)" || true
    log_captured "$HELM_BIN lint lint-set-chart --set replicaCount=5" "$set_output"
    if echo "$set_output" | grep -q "0 chart(s) failed"; then
        pass "Lint with --set override"
    else
        fail "Lint with --set override" "$set_output"
    fi
else
    fail "Lint with --set override" "helm create failed to create chart directory"
fi
rm -rf lint-set-chart

# ---------------------------------------------------------------------------
# Lint a chart with template errors
# ---------------------------------------------------------------------------
rm -rf lint-error-chart
run_cmd "$HELM_BIN" create lint-error-chart
if [[ -d lint-error-chart ]]; then
    cat > lint-error-chart/templates/bad-template.yaml << 'TMPLEOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: error-test
data:
  value: {{ .Values.nonexistent.deep.path }}
TMPLEOF
    error_output="$("$HELM_BIN" lint lint-error-chart 2>&1)" || true
    log_captured "$HELM_BIN lint lint-error-chart" "$error_output"
    if echo "$error_output" | grep -q "1 chart(s) failed"; then
        pass "Lint detects template errors"
    else
        fail "Lint detects template errors" "expected chart failure for nil-pointer template: $error_output"
    fi
else
    fail "Lint detects template errors" "helm create failed to create chart directory"
fi
rm -rf lint-error-chart

# ---------------------------------------------------------------------------
# Lint multiple charts at once
# ---------------------------------------------------------------------------
rm -rf lint-multi-a lint-multi-b
run_cmd "$HELM_BIN" create lint-multi-a
run_cmd "$HELM_BIN" create lint-multi-b
if [[ -d lint-multi-a && -d lint-multi-b ]]; then
    multi_output="$("$HELM_BIN" lint lint-multi-a lint-multi-b 2>&1)" || true
    log_captured "$HELM_BIN lint lint-multi-a lint-multi-b" "$multi_output"
    if echo "$multi_output" | grep -q "2 chart(s) linted, 0 chart(s) failed"; then
        pass "Lint multiple charts"
    else
        fail "Lint multiple charts" "$multi_output"
    fi
else
    fail "Lint multiple charts" "helm create failed to create chart directories"
fi
rm -rf lint-multi-a lint-multi-b

# ---------------------------------------------------------------------------
# Lint with --quiet flag
# ---------------------------------------------------------------------------
rm -rf lint-quiet-chart
run_cmd "$HELM_BIN" create lint-quiet-chart
if [[ -d lint-quiet-chart ]]; then
    quiet_output="$("$HELM_BIN" lint lint-quiet-chart --quiet 2>&1)" || true
    log_captured "$HELM_BIN lint lint-quiet-chart --quiet" "$quiet_output"
    if echo "$quiet_output" | grep -qi "unknown flag"; then
        skip "Lint --quiet flag" "flag not supported in this version"
    elif echo "$quiet_output" | grep -q "0 chart(s) failed"; then
        pass "Lint --quiet flag accepted"
    else
        fail "Lint --quiet flag" "expected '0 chart(s) failed' with --quiet but got: $quiet_output"
    fi
else
    fail "Lint --quiet flag" "helm create failed to create chart directory"
fi
rm -rf lint-quiet-chart

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf lint-valid-chart lint-strict-chart lint-semver-valid lint-semver-invalid \
       lint-semver-nopatch lint-semver-prerelease lint-semver-build \
       lint-values-chart lint-set-chart \
       lint-error-chart lint-multi-a lint-multi-b lint-quiet-chart \
       lint-extra-values.yaml

summary
