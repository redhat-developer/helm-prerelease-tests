# Testing Farm Integration Plan for Helm CLI Prerelease Tests

## Goal

Run the existing bash test suite on real hardware for all four Linux architectures (x86_64, aarch64, ppc64le, s390x) via Testing Farm, triggered automatically by Konflux IntegrationTestScenarios on every push snapshot.

## Prerequisites

- Testing Farm API token stored as a Kubernetes Secret in `helm-cli-tenant` namespace
- TMT test plan structure added to this repo

## Changes needed in this repo (helm-prerelease-tests)

### Add TMT metadata

```
tmt/
  plans/
    prerelease.fmf
  tests/
    run.fmf
```

#### `tmt/plans/prerelease.fmf`

```yaml
summary: Helm CLI prerelease tests
discover:
    how: fmf
    url: https://github.com/redhat-developer/helm-prerelease-tests.git
execute:
    how: tmt
prepare:
  - how: shell
    script: |
      dnf install -y podman file tar gzip
      podman create --name extract --platform linux/$(uname -m) $CONTAINER_IMAGE
      podman cp extract:/releases/. /tmp/binaries/
      podman rm extract
      chmod +x /tmp/binaries/helm-*
```

#### `tmt/tests/run.fmf`

```yaml
summary: Run prerelease test suite
test: |
  cd /tmp/binaries
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  GOARCH=amd64 ;;
    aarch64) GOARCH=arm64 ;;
    ppc64le) GOARCH=ppc64le ;;
    s390x)   GOARCH=s390x ;;
  esac
  export HELM_PLATFORM="linux-${GOARCH}"
  export VERBOSE=1

  FAIL=0
  for script in "$TMT_TREE"/scripts/{0{1,2,3,4,7,9},10}-*.sh; do
    bash "$script" || FAIL=1
  done
  exit $FAIL
duration: 15m
```

## Changes needed in konflux-release-data

### Four ITS files in `tenants-config/cluster/stone-prod-p02/tenants/helm-cli-tenant/`

One per architecture, all using the shared Testing Farm pipeline from `gitlab.com/testing-farm/integrations-konflux`.

#### Template (repeat for each arch)

```yaml
apiVersion: appstudio.redhat.com/v1beta2
kind: IntegrationTestScenario
metadata:
  labels:
    test.appstudio.openshift.io/optional: "true"
  name: helm-cli-prerelease-tests-<ARCH>
  namespace: helm-cli-tenant
spec:
  application: helm-cli
  contexts:
    - name: push
  params:
    - name: ARCH
      value: <ARCH>
    - name: COMPOSE
      value: Fedora-42
    - name: TF_GIT_URL
      value: https://github.com/redhat-developer/helm-prerelease-tests.git
    - name: TF_GIT_REF
      value: main
    - name: TF_PATH
      value: tmt
    - name: TF_PLAN
      value: /plans/prerelease
    - name: TF_TIMEOUT_MIN
      value: "30"
  resolverRef:
    resolver: git
    params:
      - name: url
        value: https://gitlab.com/testing-farm/integrations-konflux.git
      - name: revision
        value: v2.1
      - name: pathInRepo
        value: pipelines/testing-farm-container.yaml
```

#### Architectures

| ITS name | ARCH value |
|---|---|
| `helm-cli-prerelease-tests-x86-64` | `x86_64` |
| `helm-cli-prerelease-tests-aarch64` | `aarch64` |
| `helm-cli-prerelease-tests-ppc64le` | `ppc64le` |
| `helm-cli-prerelease-tests-s390x` | `s390x` |

### Update kustomization.yaml

Add all four ITS files to `tenants-config/cluster/stone-prod-p02/tenants/helm-cli-tenant/kustomization.yaml`.

### Rebuild manifests

Run `build-manifests.sh` and commit `auto-generated/` alongside the source files.

## Coverage summary

| Platform | Testing Farm | GitHub Actions | Direct Tekton ITS |
|---|---|---|---|
| linux/x86_64 | Yes | Yes | Yes |
| linux/arm64 | Yes | Yes | No |
| linux/ppc64le | Yes | No | No |
| linux/s390x | Yes | No | No |
| darwin/amd64 | No | Yes | No |
| darwin/arm64 | No | Yes | No |
| windows/amd64 | No | Yes | No |
| windows/arm64 | No | Yes | No |

## Reference implementations

- OSCI containers: `tenants-config/cluster/stone-prod-p02/tenants/osci-rhel-containers-tenant/8-10/integrationtest/shared-tfk-8-10-rhel-8-aarch64.yaml`
- OSSM ztunnel: `tenants-config/cluster/stone-prod-p02/tenants/service-mesh-tenant/ossm/ossm-3-4/integration-tests/ztunnel-it.yaml`
- Testing Farm Konflux integration repo: `https://gitlab.com/testing-farm/integrations-konflux`
