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
if printf '%s' "$version_output" | grep -qF "v${HELM_VERSION}"; then
    pass "Version check (${version_output})"
else
    fail "Version check" "expected v${HELM_VERSION}, got: $version_output"
fi

# ---------------------------------------------------------------------------
# Go version — Red Hat build
# ---------------------------------------------------------------------------
full_version="$("$HELM_BIN" version 2>&1)" || true
log_captured "$HELM_BIN version" "$full_version"
if printf '%s' "$full_version" | grep -qF "Red Hat"; then
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
if printf '%s' "$help_output" | grep -qFi "kubernetes package manager"; then
    pass "Help command"
else
    fail "Help command" "expected 'Kubernetes package manager' in help output"
fi

# ---------------------------------------------------------------------------
# Environment info
# ---------------------------------------------------------------------------
env_output="$("$HELM_BIN" env 2>&1)" || true
log_captured "$HELM_BIN env" "$env_output"
if printf '%s' "$env_output" | grep -qF "HELM_"; then
    pass "Environment info"
else
    fail "Environment info" "expected HELM_ variables in env output"
fi

# ---------------------------------------------------------------------------
# Shell completion — generation
# Assert a per-shell marker in stdout (not just non-empty, which stderr alone
# could satisfy).  Capture stdout only; discard stderr to keep noise out.
# ---------------------------------------------------------------------------
for shell_name in bash zsh fish powershell; do
    completion_exit=0
    completion_marker=""
    completion_out="$("$HELM_BIN" completion "$shell_name" 2>/dev/null)" || completion_exit=$?
    case "$shell_name" in
        bash)       completion_marker="__start_helm" ;;
        zsh)        completion_marker="compdef _helm helm" ;;
        fish)       completion_marker="complete -c helm" ;;
        powershell) completion_marker="Register-ArgumentCompleter" ;;
        *)          fail "Completion generation: $shell_name" "no marker defined for $shell_name"; continue ;;
    esac
    # Log a digest rather than the full script (VERBOSE=1 would otherwise
    # dump hundreds of lines per shell and bury the PASS:/FAIL: output).
    comp_bytes="${#completion_out}"
    comp_lines="$(printf '%s' "$completion_out" | wc -l | tr -d ' ')"
    comp_first="$(printf '%s' "$completion_out" | head -1)"
    log_captured "$HELM_BIN completion $shell_name" "${comp_bytes}B ${comp_lines}L | ${comp_first}"
    if [ "$completion_exit" -eq 0 ] && printf '%s' "$completion_out" | grep -qF "$completion_marker"; then
        pass "Completion generation: $shell_name"
    else
        fail "Completion generation: $shell_name" "exit ${completion_exit} or marker '${completion_marker}' not found"
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
    bash_result="$(COMP_FILE="$bash_comp_file" bash -c 'source "$COMP_FILE"; complete -p helm' 2>&1)" || true
    log_captured "bash -c 'source ...; complete -p helm'" "$bash_result"
    if printf '%s' "$bash_result" | grep -qF "__start_helm"; then
        pass "Completion load: bash"
    else
        fail "Completion load: bash" "__start_helm not registered: $bash_result"
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
        # Assert both: _helm function is defined AND compdef registration took
        # effect (_comps[helm] is set).  typeset -f alone passes even when the
        # compdef line is absent.  Use -d to write .zcompdump inside the
        # isolated HELM_TEST_HOME rather than the real $HOME.
        zsh_result="$(COMP_FILE="$zsh_comp_file" ZDUMP="$HELM_TEST_HOME/.zcompdump" zsh -c \
            'autoload -U compinit && compinit -u -d "$ZDUMP" || { echo compinit_failed; exit 1; }
             source "$COMP_FILE" || { echo source_failed; exit 1; }
             typeset -f _helm >/dev/null 2>&1 || { echo _helm_not_defined; exit 1; }
             [ -n "${_comps[helm]}" ] || { echo _comps_helm_not_set; exit 1; }
             echo "_helm defined, _comps[helm]=${_comps[helm]}"' 2>&1)" || true
        log_captured "zsh -c 'compinit; source ...; typeset -f _helm; _comps[helm]'" "$zsh_result"
        if printf '%s' "$zsh_result" | grep -qF "_helm defined"; then
            pass "Completion load: zsh"
        else
            fail "Completion load: zsh" "_helm not defined or compdef not registered after compinit+source: $zsh_result"
        fi
    else
        fail "Completion load: zsh" "helm completion zsh failed to generate"
    fi
else
    skip "Completion load: zsh" "zsh not available"
fi

summary
