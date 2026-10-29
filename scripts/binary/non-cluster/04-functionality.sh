#!/usr/bin/env bash
# Offline functionality tests: create, lint, template, package, show, pull, repo ops, plugins.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../common.sh"

echo ""
echo "=== 04: FUNCTIONALITY ==="
echo ""

# ---------------------------------------------------------------------------
# Create chart
# ---------------------------------------------------------------------------
rm -rf test-chart
if run_cmd "$HELM_BIN" create test-chart && [[ -f "test-chart/Chart.yaml" ]]; then
    pass "Create chart"
else
    fail "Create chart" "helm create did not produce Chart.yaml"
fi

# ---------------------------------------------------------------------------
# Lint chart
# ---------------------------------------------------------------------------
lint_output="$("$HELM_BIN" lint test-chart 2>&1)" || true
log_captured "$HELM_BIN lint test-chart" "$lint_output"
if echo "$lint_output" | grep -q "1 chart(s) linted, 0 chart(s) failed"; then
    pass "Lint chart"
else
    fail "Lint chart" "$lint_output"
fi

# ---------------------------------------------------------------------------
# Lint chart version validation
# ---------------------------------------------------------------------------
# Creates a dedicated chart (lint-ver-test) to avoid mutating the shared
# test-chart used by later sections.  For each version string, rewrite
# Chart.yaml's version field, run helm lint, and check the result.
# Three outcome classes on apiVersion v2 charts:
#   Class 1 — valid semver: exit 0, no version diagnostic
#   Class 2 — lenient semver: exit 0, WARNING naming the version
#   Class 3 — invalid semver: exit 1, ERROR naming the version

lint_ver_chart="lint-ver-test"
rm -rf "$lint_ver_chart"
if run_cmd "$HELM_BIN" create "$lint_ver_chart" && [[ -d "$lint_ver_chart" ]]; then

    # Helper: set the version field in Chart.yaml using awk (portable).
    set_chart_version() {
        awk -v ver="$1" '{
            if ($0 ~ /^version:/) print "version: " ver; else print
        }' "$lint_ver_chart/Chart.yaml" > "$lint_ver_chart/Chart.yaml.tmp" \
            && mv "$lint_ver_chart/Chart.yaml.tmp" "$lint_ver_chart/Chart.yaml"
    }

    # --- Class 1: accepted silently (valid SemVer) ---
    for ver in "1.2.3" "1.0.0-alpha.1"; do
        set_chart_version "$ver"
        lint_output="$("$HELM_BIN" lint "$lint_ver_chart" 2>&1)" || true
        log_captured "$HELM_BIN lint $lint_ver_chart (version $ver)" "$lint_output"
        if echo "$lint_output" | grep -q "0 chart(s) failed" \
           && ! echo "$lint_output" | grep -qi "version.*is not a valid"; then
            pass "Lint version accepted silently: $ver"
        else
            fail "Lint version accepted silently: $ver" "$lint_output"
        fi
    done

    # --- Class 2: accepted with warning (lenient semver) ---
    for ver in "v1" "1.2"; do
        set_chart_version "$ver"
        lint_output="$("$HELM_BIN" lint "$lint_ver_chart" 2>&1)" || true
        log_captured "$HELM_BIN lint $lint_ver_chart (version $ver)" "$lint_output"
        if echo "$lint_output" | grep -q "0 chart(s) failed" \
           && echo "$lint_output" | grep -F '[WARNING]' | grep -Fq "$ver"; then
            pass "Lint version warning: $ver"
        else
            fail "Lint version warning: $ver" "$lint_output"
        fi
    done

    # --- Class 3: rejected (invalid semver) ---
    for ver in "1.2.3.4" "abc"; do
        set_chart_version "$ver"
        lint_output="$("$HELM_BIN" lint "$lint_ver_chart" 2>&1)"
        lint_exit=$?
        log_captured "$HELM_BIN lint $lint_ver_chart (version $ver)" "$lint_output"
        if [[ $lint_exit -ne 0 ]] \
           && echo "$lint_output" | grep -q "1 chart(s) failed" \
           && echo "$lint_output" | grep -Fq "$ver"; then
            pass "Lint version rejected: $ver"
        else
            fail "Lint version rejected: $ver" "exit=$lint_exit output=$lint_output"
        fi
    done

else
    skip "Lint version accepted silently: 1.2.3" "helm create failed"
    skip "Lint version accepted silently: 1.0.0-alpha.1" "helm create failed"
    skip "Lint version warning: v1" "helm create failed"
    skip "Lint version warning: 1.2" "helm create failed"
    skip "Lint version rejected: 1.2.3.4" "helm create failed"
    skip "Lint version rejected: abc" "helm create failed"
fi
rm -rf "$lint_ver_chart"

# ---------------------------------------------------------------------------
# Template chart
# ---------------------------------------------------------------------------
template_output="$("$HELM_BIN" template test-chart test-chart 2>&1)" || true
log_captured "$HELM_BIN template test-chart test-chart" "$template_output"
if echo "$template_output" | grep -q "apiVersion:"; then
    pass "Template chart"
else
    fail "Template chart" "no apiVersion in template output"
fi

# ---------------------------------------------------------------------------
# Package chart
# ---------------------------------------------------------------------------
rm -f test-chart-*.tgz
if run_cmd "$HELM_BIN" package test-chart; then
    if ls test-chart-*.tgz &>/dev/null; then
        pass "Package chart"
    else
        fail "Package chart" "no .tgz file produced"
    fi
else
    fail "Package chart" "helm package failed"
fi

# ---------------------------------------------------------------------------
# Show chart metadata
# ---------------------------------------------------------------------------
show_output="$("$HELM_BIN" show chart test-chart 2>&1)" || true
log_captured "$HELM_BIN show chart test-chart" "$show_output"
if echo "$show_output" | grep -q "name: test-chart"; then
    pass "Show chart metadata"
else
    fail "Show chart metadata" "expected chart name in output"
fi

# ---------------------------------------------------------------------------
# Repo add / list / search / remove
# ---------------------------------------------------------------------------
run_cmd "$HELM_BIN" repo add stable https://charts.helm.sh/stable || true
repo_list="$("$HELM_BIN" repo list 2>&1)" || true
log_captured "$HELM_BIN repo list" "$repo_list"
if echo "$repo_list" | grep -q "stable"; then
    pass "Repo add and list"
else
    fail "Repo add and list" "stable repo not in list"
fi

search_output="$("$HELM_BIN" search repo stable/mysql --versions 2>&1)" || true
log_captured "$HELM_BIN search repo stable/mysql --versions" "$search_output"
if echo "$search_output" | grep -q "mysql"; then
    pass "Repo search"
else
    fail "Repo search" "mysql not found in search results"
fi

if run_cmd "$HELM_BIN" repo remove stable; then
    pass "Repo remove"
else
    fail "Repo remove" "helm repo remove failed"
fi

# ---------------------------------------------------------------------------
# Pull chart
# ---------------------------------------------------------------------------
run_cmd "$HELM_BIN" repo add stable https://charts.helm.sh/stable || true
rm -f mysql-1.6.9.tgz
if run_cmd "$HELM_BIN" pull stable/mysql --version 1.6.9 && [[ -f "mysql-1.6.9.tgz" ]]; then
    pass "Pull chart"
else
    fail "Pull chart" "mysql-1.6.9.tgz not downloaded"
fi
rm -f mysql-1.6.9.tgz
run_cmd "$HELM_BIN" repo remove stable || true

# ---------------------------------------------------------------------------
# Plugin list
# ---------------------------------------------------------------------------
plugin_output="$("$HELM_BIN" plugin list 2>&1)" || true
log_captured "$HELM_BIN plugin list" "$plugin_output"
if echo "$plugin_output" | grep -qiE "NAME.*VERSION.*TYPE|APIVERSION"; then
    pass "Plugin list (v4 columns)"
else
    fail "Plugin list" "expected v4 column headers in: $plugin_output"
fi

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf test-chart test-chart-*.tgz

summary
