#!/usr/bin/env bash
# Container image checks for the helm-cli Konflux build.
# Verifies image labels, entrypoint binary presence, and version output.
#
# Required env vars (set by the Tekton pipeline):
#   BINARY_IMAGE — full image reference to inspect (e.g. quay.io/...@sha256:...)
#   HELM_BIN     — path to the extracted /usr/local/bin/helm binary
#
# Requires skopeo on PATH (installed by the pipeline step before invoking this script).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/../common.sh"

echo "=== 01: IMAGE CHECKS ==="
echo "BINARY_IMAGE: ${BINARY_IMAGE:-<unset>}"
echo "HELM_BIN:     ${HELM_BIN:-<unset>}"
echo ""

# ---------------------------------------------------------------------------
# Guard: both env vars must be set
# ---------------------------------------------------------------------------
if [[ -z "${BINARY_IMAGE:-}" ]]; then
    echo "FATAL: BINARY_IMAGE is not set — cannot run container checks"
    exit 1
fi
if [[ -z "${HELM_BIN:-}" ]]; then
    echo "FATAL: HELM_BIN is not set — cannot run version checks"
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. Label checks via skopeo inspect
# ---------------------------------------------------------------------------
echo "--- label checks ---"

INSPECT_JSON=$(skopeo inspect "docker://${BINARY_IMAGE}" 2>&1) || {
    fail "skopeo inspect" "skopeo exited non-zero: ${INSPECT_JSON}"
    summary
    exit 1
}

NAME=$(echo    "$INSPECT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Labels',{}).get('name',''))")
VERSION=$(echo "$INSPECT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Labels',{}).get('version',''))")
RELEASE=$(echo "$INSPECT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Labels',{}).get('release',''))")
CPE=$(echo     "$INSPECT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Labels',{}).get('cpe',''))")

log_verbose "name=${NAME}  version=${VERSION}  release=${RELEASE}  cpe=${CPE}"

if [[ "$NAME" == "helm-cli/helm-cli-rhel9" ]]; then
    pass "label:name"
else
    fail "label:name" "expected 'helm-cli/helm-cli-rhel9', got '${NAME}'"
fi

if [[ -n "$VERSION" ]]; then
    pass "label:version (${VERSION})"
else
    fail "label:version" "missing or empty"
fi

if [[ -n "$RELEASE" ]]; then
    pass "label:release (${RELEASE})"
else
    fail "label:release" "missing or empty"
fi

# CPE must be the stream CPE (major.minor, not patch): cpe:/a:redhat:helm_cli:X.Y::el9
if echo "$CPE" | grep -qE '^cpe:/a:redhat:helm_cli:[0-9]+\.[0-9]+::el9$'; then
    pass "label:cpe (${CPE})"
else
    fail "label:cpe" "expected stream CPE cpe:/a:redhat:helm_cli:X.Y::el9, got '${CPE}'"
fi

# ---------------------------------------------------------------------------
# 2. Entrypoint binary checks
# ---------------------------------------------------------------------------
echo ""
echo "--- entrypoint binary checks ---"

if [[ ! -f "$HELM_BIN" ]]; then
    fail "helm binary present" "${HELM_BIN} not found"
    summary
    exit 1
fi
pass "helm binary present (${HELM_BIN})"

chmod +x "$HELM_BIN"

run_capture "$HELM_BIN" version --template '{{.Version}}'
HELM_VERSION_OUTPUT="$LAST_OUTPUT"
log_captured "helm version" "$HELM_VERSION_OUTPUT"

if echo "$HELM_VERSION_OUTPUT" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+'; then
    pass "helm version returns valid semver (${HELM_VERSION_OUTPUT})"
else
    fail "helm version" "expected vX.Y.Z, got '${HELM_VERSION_OUTPUT}'"
fi

# Version label (e.g. "4.3.0") must appear in binary output (e.g. "v4.3.0")
if [[ -n "$VERSION" ]]; then
    if echo "$HELM_VERSION_OUTPUT" | grep -qF "$VERSION"; then
        pass "version matches label (label=${VERSION}, binary=${HELM_VERSION_OUTPUT})"
    else
        fail "version mismatch" "label=${VERSION}, binary reports ${HELM_VERSION_OUTPUT}"
    fi
fi

summary
