# helm-prerelease-tests

Automated cross-platform binary validation for Red Hat Helm distributions. Tests binary artifacts from Konflux builds across linux (amd64, arm64, ppc64le, s390x), macOS (amd64, arm64), and Windows (amd64, arm64).

## What this does

Shell test scripts verify that downstream Red Hat helm v4 binaries are correctly built, distributed, and functional. Each script runs a category of tests and emits `PASS:`/`FAIL:`/`SKIP:` lines for machine-parseable results.

## Platforms

| Platform | CI (GitHub Actions) | Manual |
|---|---|---|
| linux-amd64 | yes | — |
| linux-arm64 | yes | — |
| linux-ppc64le | — | Testing Farms |
| linux-s390x | — | Testing Farms |
| darwin-amd64 | yes | — |
| darwin-arm64 | yes | — |
| win-amd64 | yes | — |
| win-arm64 | yes | — |

## Test categories

`scripts/binary/non-cluster/` — run on all platforms, no cluster needed:

| Script | Category |
|---|---|
| 01-validation.sh | Checksums, file type, arch, permissions, size |
| 02-smoke.sh | Version, help, env |
| 03-dependencies.sh | Static linking verification |
| 04-functionality.sh | Create, lint, template, package, show, pull, repo ops |
| 05-v4-features.sh | v4-specific offline feature tests |
| 06-distribution.sh | Archive extraction (.tar.gz, .zip) |

`scripts/binary/cluster/` — require a live Kubernetes cluster (self-skip when absent):

| Script | Category |
|---|---|
| 01-functionality.sh | Install, upgrade, rollback, uninstall |
| 02-oci.sh | OCI push, install, install by digest |
| 03-v4-features.sh | v4-specific cluster feature tests |

`scripts/container/` — container image checks (separate pipeline):

| Script | What it checks |
|---|---|
| 01-image-checks.sh | Image labels (`name`, `version`, `release`, stream `cpe`), entrypoint binary presence, `helm version` |
| 02-non-cluster-suite.sh | Runs the non-cluster binary suite against `/usr/local/bin/helm` from the container (cluster tests for the container are a separate future effort) |

## Running locally

**Binary scripts:**

```shell
export BINARY_IMAGE="quay.io/redhat-user-workloads/helm-cli-tenant/helm-cli@sha256:<image-sha>"
source scripts/common.sh
./scripts/binary/non-cluster/01-validation.sh
```

**Container scripts** (requires `skopeo` on PATH):

```shell
export BINARY_IMAGE="quay.io/redhat-user-workloads/helm-cli-tenant/helm-cli@sha256:<image-sha>"
export HELM_BIN="/path/to/extracted/helm"   # extract from /usr/local/bin/ of the image first
./scripts/container/01-image-checks.sh
./scripts/container/02-non-cluster-suite.sh
```

The image is a multi-arch manifest, so on a non-linux/amd64 host (e.g. an Apple Silicon
Mac) a bare `skopeo inspect` fails with "no image found in manifest list". Run the
scripts inside a `linux/amd64` container to match the pipeline environment:

```shell
podman run --rm --platform linux/amd64 -v "$(pwd)":/tests:ro \
  -e BINARY_IMAGE -e HELM_BIN=/tmp/helm \
  registry.access.redhat.com/ubi9/ubi-minimal:latest bash -c '
    microdnf install -y skopeo python3 --nodocs --setopt=install_weak_deps=0
    bash /tests/scripts/container/01-image-checks.sh'
```

## Binary source

Binaries are extracted from a Konflux-built container image on quay.io. The image SHA is passed via `BINARY_IMAGE` environment variable or `workflow_dispatch` input.
