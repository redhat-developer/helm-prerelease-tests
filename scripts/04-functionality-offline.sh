#!/usr/bin/env bash
# Offline functionality tests: create, lint, template, package, show, pull, repo ops, plugins.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo ""
echo "=== 04: FUNCTIONALITY (OFFLINE) ==="
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
if echo "$lint_output" | grep -q "1 chart(s) linted, 0 chart(s) failed"; then
    pass "Lint chart"
else
    fail "Lint chart" "$lint_output"
fi

# ---------------------------------------------------------------------------
# Template chart
# ---------------------------------------------------------------------------
template_output="$("$HELM_BIN" template test-chart test-chart 2>&1)" || true
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
if echo "$repo_list" | grep -q "stable"; then
    pass "Repo add and list"
else
    fail "Repo add and list" "stable repo not in list"
fi

search_output="$("$HELM_BIN" search repo stable/mysql --versions 2>&1)" || true
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
