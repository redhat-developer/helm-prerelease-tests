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

| Script | Category | Cluster required |
|---|---|---|
| 01-validation.sh | Checksums, file type, arch, permissions, size | no |
| 02-smoke.sh | Version, help, env | no |
| 03-dependencies.sh | Static linking verification | no |
| 04-functionality-offline.sh | Create, lint, template, package, show, pull, repo ops | no |
| 05-functionality-cluster.sh | Install, upgrade, rollback, uninstall | yes |
| 06-oci.sh | OCI push, install, install by digest | yes |
| 07-v4-features-offline.sh | v4-specific offline feature tests | no |
| 08-v4-features-cluster.sh | v4-specific cluster feature tests | yes |
| 09-distribution.sh | Archive extraction (.tar.gz, .zip) | no |

## Running locally

```shell
export BINARY_IMAGE="quay.io/redhat-user-workloads/helm-cli-tenant/helm-cli@sha256:<image-sha>"
source scripts/common.sh
./scripts/01-validation.sh
```

## Binary source

Binaries are extracted from a Konflux-built container image on quay.io. The image SHA is passed via `BINARY_IMAGE` environment variable or `workflow_dispatch` input.
