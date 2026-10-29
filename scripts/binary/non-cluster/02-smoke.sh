#!/usr/bin/env bash
# Smoke tests: version, Go version, help output, environment info, shell completion generation and load.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../common.sh"

echo ""
echo "=== 02: SMOKE TESTS ==="
echo ""

# ---------------------------------------------------------------------------
# Version check
# ---------------------------------------------------------------------------
version_output="$("$HELM_BIN" version --short 2>&1)" || true
log_captured "$HELM_BIN version --short" "$version_output"
if echo "$version_output" | grep -q "v${HELM_VERSION}"; then
    pass "Version check (${version_output})"
else
    fail "Version check" "expected v${HELM_VERSION}, got: $version_output"
fi

# ---------------------------------------------------------------------------
# Go version — Red Hat build
# ---------------------------------------------------------------------------
full_version="$("$HELM_BIN" version 2>&1)" || true
log_captured "$HELM_BIN version" "$full_version"
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
log_captured "$HELM_BIN help" "$help_output"
if echo "$help_output" | grep -qi "kubernetes package manager"; then
    pass "Help command"
else
    fail "Help command" "expected 'Kubernetes package manager' in help output"
fi

# ---------------------------------------------------------------------------
# Environment info
# ---------------------------------------------------------------------------
env_output="$("$HELM_BIN" env 2>&1)" || true
log_captured "$HELM_BIN env" "$env_output"
if echo "$env_output" | grep -q "HELM_"; then
    pass "Environment info"
else
    fail "Environment info" "expected HELM_ variables in env output"
fi

# ---------------------------------------------------------------------------
# Shell completion — generation
# ---------------------------------------------------------------------------
for shell_name in bash zsh fish powershell; do
    completion_exit=0
    completion_out="$("$HELM_BIN" completion "$shell_name" 2>&1)" || completion_exit=$?
    log_captured "$HELM_BIN completion $shell_name" "$completion_out"
    if [ "$completion_exit" -eq 0 ] && [ -n "$completion_out" ]; then
        pass "Completion generation: $shell_name"
    else
        fail "Completion generation: $shell_name" "exit ${completion_exit} or empty output"
    fi
done

# ---------------------------------------------------------------------------
# Shell completion — bash load test
# No availability guard needed: bash is the script's own runtime and
# `complete` works in non-interactive bash -c subshells on all platforms.
# (Contrast the zsh block below, which guards with `command -v zsh`.)
# ---------------------------------------------------------------------------
bash_comp_file="${HELM_TEST_HOME}/helm-completion.bash"
if "$HELM_BIN" completion bash > "$bash_comp_file" 2>/dev/null; then
    load_result="$(COMP_FILE="$bash_comp_file" bash -c 'source "$COMP_FILE"; complete -p helm' 2>&1)" || true
    log_captured "bash -c 'source ...; complete -p helm'" "$load_result"
    if echo "$load_result" | grep -q "__start_helm"; then
        pass "Completion load: bash"
    else
        fail "Completion load: bash" "__start_helm not registered: $load_result"
    fi
else
    fail "Completion load: bash" "helm completion bash failed to generate"
fi

# ---------------------------------------------------------------------------
# Shell completion — zsh load test
# ---------------------------------------------------------------------------
if command -v zsh > /dev/null 2>&1; then
    zsh_comp_file="${HELM_TEST_HOME}/helm-completion.zsh"
    if "$HELM_BIN" completion zsh > "$zsh_comp_file" 2>/dev/null; then
        zsh_result="$(COMP_FILE="$zsh_comp_file" zsh -c 'autoload -U compinit && compinit -u && source "$COMP_FILE" && typeset -f _helm >/dev/null 2>&1 && echo "_helm defined"' 2>&1)" || true
        log_captured "zsh -c 'compinit; source ...; typeset -f _helm'" "$zsh_result"
        if echo "$zsh_result" | grep -q "_helm defined"; then
            pass "Completion load: zsh"
        else
            fail "Completion load: zsh" "_helm not defined after compinit+source: $zsh_result"
        fi
    else
        fail "Completion load: zsh" "helm completion zsh failed to generate"
    fi
else
    skip "Completion load: zsh" "zsh not available"
fi

summary
