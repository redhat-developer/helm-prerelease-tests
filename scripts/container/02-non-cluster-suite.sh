#!/usr/bin/env bash
# Runs the non-cluster binary test suite against the helm binary from the
# container entrypoint (/usr/local/bin/helm), validating that what ships
# inside the container passes the same checks as the extracted release binary.
#
# Non-cluster only — cluster-based container tests are a separate future effort.
#
# Required env vars (set by the Tekton pipeline):
#   HELM_BIN — path to the extracted /usr/local/bin/helm binary

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NON_CLUSTER="$SCRIPT_DIR/../binary/non-cluster"

if [[ -z "${HELM_BIN:-}" ]]; then
    echo "FATAL: HELM_BIN is not set"
    exit 1
fi

if [[ ! -f "$HELM_BIN" ]]; then
    echo "FATAL: HELM_BIN=${HELM_BIN} not found"
    exit 1
fi

chmod +x "$HELM_BIN"

echo "=== 02: NON-CLUSTER BINARY SUITE (CONTAINER ENTRYPOINT) ==="
echo "HELM_BIN: ${HELM_BIN}"
echo ""

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
FAILED_SUITES=()

# 01-validation and 06-distribution require sha256sum.txt from the release
# archive, which is not present in the container context — skip them here.
for script in "$NON_CLUSTER"/*.sh; do
    suite="$(basename "$script" .sh)"
    case "$suite" in
        01-validation|06-distribution) continue ;;
    esac
    echo "================================================================"
    echo "Running: ${suite}"
    echo "================================================================"

    tmplog=$(mktemp)
    bash "$script" 2>&1 | tee "$tmplog"
    rc=${PIPESTATUS[0]}

    totals=$(grep -E '^TOTAL:' "$tmplog" || true)
    if [[ -n "$totals" ]]; then
        p=$(echo "$totals" | grep -oP 'PASS: \K[0-9]+' || echo 0)
        f=$(echo "$totals" | grep -oP 'FAIL: \K[0-9]+' || echo 0)
        s=$(echo "$totals" | grep -oP 'SKIP: \K[0-9]+' || echo 0)
        TOTAL_PASS=$((TOTAL_PASS + p))
        TOTAL_FAIL=$((TOTAL_FAIL + f))
        TOTAL_SKIP=$((TOTAL_SKIP + s))
    fi

    rm -f "$tmplog"
    [[ $rc -ne 0 ]] && FAILED_SUITES+=("$suite")
    echo ""
done

echo "================================================================"
echo "TOTAL: $((TOTAL_PASS + TOTAL_FAIL + TOTAL_SKIP))  PASS: ${TOTAL_PASS}  FAIL: ${TOTAL_FAIL}  SKIP: ${TOTAL_SKIP}"
if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
    echo "FAILURES:"
    for s in "${FAILED_SUITES[@]}"; do echo "  - ${s}"; done
fi

[[ $TOTAL_FAIL -eq 0 ]]
