#!/usr/bin/env bash
# v4-specific feature tests that do not require a cluster.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo ""
echo "=== 07: V4 FEATURES (OFFLINE) ==="
echo ""

# ---------------------------------------------------------------------------
# 1. Multi-document values
# ---------------------------------------------------------------------------
rm -rf v4-values-test
"$HELM_BIN" create v4-values-test &>/dev/null
cat > values-base.yaml << 'VALEOF'
replicaCount: 1
image:
  tag: "base"
VALEOF
cat > values-override.yaml << 'VALEOF'
image:
  tag: "override"
VALEOF
template_output="$("$HELM_BIN" template v4-values-test v4-values-test -f values-base.yaml -f values-override.yaml 2>&1)" || true
if echo "$template_output" | grep -q "override"; then
    pass "Multi-document values"
else
    fail "Multi-document values" "override tag not found in output"
fi
rm -f values-base.yaml values-override.yaml
rm -rf v4-values-test

# ---------------------------------------------------------------------------
# 2. JSON arguments (--set-json)
# ---------------------------------------------------------------------------
rm -rf v4-json-test
"$HELM_BIN" create v4-json-test &>/dev/null
template_output="$("$HELM_BIN" template v4-json-test v4-json-test --set-json 'replicaCount=3' 2>&1)" || true
if echo "$template_output" | grep -q "replicas: 3"; then
    pass "JSON arguments (--set-json)"
else
    fail "JSON arguments (--set-json)" "replicas: 3 not found in output"
fi
rm -rf v4-json-test

# ---------------------------------------------------------------------------
# 3. Post-renderers as plugins
# ---------------------------------------------------------------------------
rm -rf v4-pr-test
"$HELM_BIN" create v4-pr-test &>/dev/null
pr_output="$("$HELM_BIN" template v4-pr-test v4-pr-test --post-renderer /usr/bin/cat 2>&1)" || true
if echo "$pr_output" | grep -qi "not found\|invalid argument"; then
    pass "Post-renderers as plugins (rejects executable path)"
else
    fail "Post-renderers as plugins" "expected plugin-not-found error: $pr_output"
fi
rm -rf v4-pr-test

# ---------------------------------------------------------------------------
# 4. Plugin system check
# ---------------------------------------------------------------------------
plugin_output="$("$HELM_BIN" plugin list 2>&1)" || true
if echo "$plugin_output" | grep -qi "APIVERSION"; then
    pass "Plugin system check (apiVersion column)"
else
    fail "Plugin system check" "apiVersion column not found"
fi

# ---------------------------------------------------------------------------
# 5. Registry login domain-only
# ---------------------------------------------------------------------------
login_scheme="$("$HELM_BIN" registry login https://registry.example.com -u test -p test 2>&1)" || true
login_path="$("$HELM_BIN" registry login ghcr.io/myrepo -u test -p test 2>&1)" || true
if echo "$login_scheme" | grep -qi "scheme\|invalid\|error" && echo "$login_path" | grep -qi "path\|invalid\|error"; then
    pass "Registry login domain-only (rejects scheme and path)"
else
    fail "Registry login domain-only" "scheme: $login_scheme | path: $login_path"
fi

# ---------------------------------------------------------------------------
# 6. Version shows kube version
# ---------------------------------------------------------------------------
version_output="$("$HELM_BIN" version 2>&1)" || true
if echo "$version_output" | grep -qi "KubeClientVersion\|client-go"; then
    pass "Version shows kube version"
else
    fail "Version shows kube version" "no kube version in: $version_output"
fi

# ---------------------------------------------------------------------------
# 7. Repo list --no-headers
# ---------------------------------------------------------------------------
"$HELM_BIN" repo add test-nh https://charts.helm.sh/stable &>/dev/null || true
noheader_output="$("$HELM_BIN" repo list --no-headers 2>&1)" || true
if echo "$noheader_output" | grep -q "test-nh" && ! echo "$noheader_output" | grep -qi "^NAME"; then
    pass "Repo list --no-headers"
else
    fail "Repo list --no-headers" "header line present or repo missing"
fi
"$HELM_BIN" repo remove test-nh &>/dev/null || true

# ---------------------------------------------------------------------------
# 8. --skip-schema-validation
# ---------------------------------------------------------------------------
rm -rf v4-schema-test
"$HELM_BIN" create v4-schema-test &>/dev/null
cat > v4-schema-test/values.schema.json << 'SCHEMAEOF'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["requiredField"],
  "properties": {
    "requiredField": {"type": "string"}
  }
}
SCHEMAEOF
lint_fail="$("$HELM_BIN" lint v4-schema-test 2>&1)" || true
lint_skip="$("$HELM_BIN" lint v4-schema-test --skip-schema-validation 2>&1)" || true
if echo "$lint_fail" | grep -qi "requiredField\|schema" && echo "$lint_skip" | grep -q "0 chart(s) failed"; then
    pass "--skip-schema-validation"
else
    fail "--skip-schema-validation" "without flag: $lint_fail | with flag: $lint_skip"
fi
rm -rf v4-schema-test

# ---------------------------------------------------------------------------
# 9-13. Removed flags
# ---------------------------------------------------------------------------
for flag_test in \
    "install --create-pods:--create-pods" \
    "repo add --no-update stable https://charts.helm.sh/stable:--no-update" \
    "status --show-desc test:--show-desc" \
    "status --show-resources test:--show-resources" \
    "version --client:--client"; do

    cmd="${flag_test%%:*}"
    flag_name="${flag_test##*:}"
    output="$("$HELM_BIN" $cmd 2>&1)" || true
    if echo "$output" | grep -qi "unknown flag"; then
        pass "Removed flag: ${flag_name}"
    else
        fail "Removed flag: ${flag_name}" "expected unknown flag error: $output"
    fi
done

# ---------------------------------------------------------------------------
# 14-15. Deprecated template flags
# ---------------------------------------------------------------------------
rm -rf v4-dep-flag-test
"$HELM_BIN" create v4-dep-flag-test &>/dev/null

for flag in "--hide-notes" "--render-subchart-notes"; do
    template_out="$("$HELM_BIN" template v4-dep-flag-test v4-dep-flag-test $flag 2>&1)" || true
    if echo "$template_out" | grep -q "apiVersion:"; then
        pass "Deprecated flag: ${flag} (accepted silently)"
    else
        fail "Deprecated flag: ${flag}" "template failed: $template_out"
    fi
done

# Check if flags are hidden from help (v4.2.0+ only)
if skip_if_below "Deprecated flags hidden from --help" "4.2.0"; then
    help_out="$("$HELM_BIN" template --help 2>&1)" || true
    if ! echo "$help_out" | grep -qE "hide-notes|render-subchart-notes"; then
        pass "Deprecated flags hidden from --help"
    else
        fail "Deprecated flags hidden from --help" "flags still visible in help"
    fi
fi

rm -rf v4-dep-flag-test

# ---------------------------------------------------------------------------
# 16. mustToYaml / mustToJson template functions
# ---------------------------------------------------------------------------
rm -rf v4-mustfunc-test
"$HELM_BIN" create v4-mustfunc-test &>/dev/null
cat > v4-mustfunc-test/templates/test-mustfunc.yaml << 'TMPLEOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: mustfunc-test
data:
  asYaml: |
    {{ .Values.testData | mustToYaml | nindent 4 }}
  asJson: |
    {{ .Values.testData | mustToJson | nindent 4 }}
TMPLEOF
cat > v4-mustfunc-test/test-values.yaml << 'VALEOF'
testData:
  key1: value1
  key2: value2
VALEOF
mustfunc_out="$("$HELM_BIN" template v4-mustfunc-test v4-mustfunc-test -f v4-mustfunc-test/test-values.yaml 2>&1)" || true
if echo "$mustfunc_out" | grep -q "key1: value1" && echo "$mustfunc_out" | grep -q '"key1"'; then
    pass "mustToYaml/mustToJson functions"
else
    fail "mustToYaml/mustToJson functions" "expected YAML and JSON output"
fi
rm -rf v4-mustfunc-test

# ---------------------------------------------------------------------------
# 17. Lint CRD directory
# ---------------------------------------------------------------------------
rm -rf v4-crd-test
"$HELM_BIN" create v4-crd-test &>/dev/null
mkdir -p v4-crd-test/crds
cat > v4-crd-test/crds/test-crd.yaml << 'CRDEOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: tests.example.com
spec:
  group: example.com
  names:
    kind: Test
    plural: tests
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
CRDEOF
crd_lint="$("$HELM_BIN" lint v4-crd-test 2>&1)" || true
if echo "$crd_lint" | grep -q "0 chart(s) failed"; then
    pass "Lint CRD directory"
else
    fail "Lint CRD directory" "$crd_lint"
fi
rm -rf v4-crd-test

# ---------------------------------------------------------------------------
# 18. Lint .yml files
# ---------------------------------------------------------------------------
rm -rf v4-yml-test
"$HELM_BIN" create v4-yml-test &>/dev/null
cat > v4-yml-test/templates/bad.yml << 'YMLEOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: yml-test
data:
  value: {{ .Values.nonexistent.deep.path }}
YMLEOF
yml_lint="$("$HELM_BIN" lint v4-yml-test 2>&1)" || true
if echo "$yml_lint" | grep -qi "error\|bad.yml"; then
    pass "Lint .yml files (lints same as .yaml)"
else
    fail "Lint .yml files" "expected lint error on bad.yml"
fi
rm -rf v4-yml-test

# ---------------------------------------------------------------------------
# 19. Content-based caching
# ---------------------------------------------------------------------------
env_output="$("$HELM_BIN" env 2>&1)" || true
if echo "$env_output" | grep -qi "HELM_CONTENT_CACHE\|content"; then
    pass "Content-based caching (HELM_CONTENT_CACHE in env)"
else
    fail "Content-based caching" "HELM_CONTENT_CACHE not found in env"
fi

# ---------------------------------------------------------------------------
# 20. mustToToml function (v4.2.0+)
# ---------------------------------------------------------------------------
if skip_if_below "mustToToml function" "4.2.0"; then
    rm -rf v4-toml-test
    "$HELM_BIN" create v4-toml-test &>/dev/null
    cat > v4-toml-test/templates/test-toml.yaml << 'TMPLEOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: toml-test
data:
  config.toml: |
    {{ .Values.tomlData | mustToToml | nindent 4 }}
TMPLEOF
    cat > v4-toml-test/test-values.yaml << 'VALEOF'
tomlData:
  title: "Test"
  database:
    server: "192.168.1.1"
    port: 5432
VALEOF
    toml_out="$("$HELM_BIN" template v4-toml-test v4-toml-test -f v4-toml-test/test-values.yaml 2>&1)" || true
    if echo "$toml_out" | grep -q "title"; then
        pass "mustToToml function"
    else
        fail "mustToToml function" "$toml_out"
    fi
    rm -rf v4-toml-test
fi

# ---------------------------------------------------------------------------
# 21. JSON Schema 2020 support
# ---------------------------------------------------------------------------
rm -rf v4-schema2020-test
"$HELM_BIN" create v4-schema2020-test &>/dev/null
cat > v4-schema2020-test/values.schema.json << 'SCHEMAEOF'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "replicaCount": {
      "type": "integer",
      "minimum": 1
    }
  }
}
SCHEMAEOF
schema2020_lint="$("$HELM_BIN" lint v4-schema2020-test 2>&1)" || true
if echo "$schema2020_lint" | grep -q "0 chart(s) failed"; then
    pass "JSON Schema 2020 support"
else
    fail "JSON Schema 2020 support" "$schema2020_lint"
fi
rm -rf v4-schema2020-test

summary
