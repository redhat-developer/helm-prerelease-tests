# CLAUDE.md

Guidance for Claude (and other AI agents, including fullsend's automated agents) working in this repo.

## What this repo is

Downstream Red Hat packaging QA for the Helm CLI. This repo currently validates that the **binary artifacts** Red Hat ships for Helm are correctly built, distributed, and functional. It is not a Helm migration or usage guide.

**Scope:** binary artifacts and container image. RPM packaging is not yet tested — add coverage when Red Hat starts releasing RPMs.

The binaries under test are extracted from a Konflux-built container image on `quay.io` (see `image.env` for the current pinned `BINARY_IMAGE` digest). Each test script runs a category of checks against those extracted binaries and emits machine-parseable `PASS:` / `FAIL:` / `SKIP:` lines.

Seven platform targets matter for sign-off: `linux-amd64`, `linux-arm64`, `linux-ppc64le`, `linux-s390x`, `darwin-amd64`, `darwin-arm64`, `windows-amd64` (Windows `arm64` is also present in CI but is not one of the required seven).

## Repository layout

| Path | Purpose |
|---|---|
| `scripts/common.sh` | Shared shell library: platform detection, `pass`/`fail`/`skip` helpers, `HELM_BIN` resolution, isolated `HELM_*_HOME`, cluster detection. Sourced by every script, never run directly. |
| `scripts/binary/non-cluster/` | Binary test scripts that run on every platform without a cluster (see table below). |
| `scripts/binary/cluster/` | Binary test scripts that require a live Kubernetes cluster (self-skip when absent). |
| `scripts/container/` | Container image checks — separate pipeline, different env vars (`BINARY_IMAGE`, `HELM_BIN`). |
| `image.env` | Pins the `BINARY_IMAGE` digest that GitHub Actions CI (and local runs) test against — see below for why this still exists alongside Konflux. |
| `.github/workflows/test-binary.yml` | GitHub Actions CI: extracts binaries from the image in `image.env`, runs non-cluster scripts on all platforms and cluster scripts on Linux (with a real `kind` cluster). |
| `.tekton/helm-prerelease-tests-pipeline.yaml` | Konflux binary test pipeline. Extracts binaries from the `SNAPSHOT`, runs `scripts/binary/non-cluster/` only — no cluster available in the Konflux runner. |
| `.tekton/helm-container-tests-pipeline.yaml` | Konflux container test pipeline. Inspects the `SNAPSHOT` image labels and entrypoint binary. |
| `.fmf/version` | Marks this repo as an fmf metadata tree root. Testing Farm finds no plans without it. Contents: `1`. |
| `plans/non-cluster.fmf`, `plans/cluster.fmf` | tmt plans run by Testing Farm. Envelopes only — they extract the binary from `IMAGE_URL` and invoke the same `scripts/` suites every other runner uses. See below. |
| `.fullsend/config.yaml`, `.github/workflows/fullsend.yaml`, `.github/workflows/prioritize.yml` | fullsend automation wiring — see below. |

`linux-ppc64le` / `linux-s390x` have no automated coverage in this repo today — they're tested manually, outside CI. The `plans/` directory is the in-progress fix (HELM-849); it is inert until the matching IntegrationTestScenarios merge in `konflux-release-data`.

### Testing Farm plans (`plans/`)

Testing Farm provisions a guest of the requested architecture, clones this repo, finds `.fmf/version`, and runs the plan named by the ITS `TMT_PLAN` param. The plan's `prepare` phase pulls the snapshot image and copies the native binary out of `/releases/`; its `discover` phase loops the existing `scripts/binary/{non-cluster,cluster}/*.sh`.

Two consequences worth remembering:

- **The plans hold no assertions.** Add a non-cluster test case to a script and it runs on every runner — GitHub Actions, the Konflux amd64 gate, and all four Testing Farm architectures — with no plan change. Cluster test cases run only on GitHub Actions (with `kind`) and Testing Farm for x86_64/aarch64; they are excluded from the Konflux pipeline entirely.
- **The directory split is the contract.** A cluster-dependent script placed in `non-cluster/` will be picked up by the non-cluster plan and run on a guest with no cluster.

`plans/cluster.fmf` is x86_64/aarch64 only — `kindest/node` ships amd64 and arm64 images only — and fails loudly on other architectures rather than skipping.

**Why both `image.env` and `.tekton/` exist:** `image.env` predates the Konflux pipeline. Once Konflux started injecting the `SNAPSHOT` directly, `image.env` became redundant for that path. It's still here because **Konflux's pipeline doesn't run cluster-based tests**, and GitHub Actions' `kind`-backed runners do. `image.env` is what keeps GHA running the cluster suite — it is not a leftover to clean up.

## Test categories

**`scripts/binary/non-cluster/`** — no cluster required, run on all platforms:

| Script | Category |
|---|---|
| `01-validation.sh` | Checksums, file type, arch match, permissions, size |
| `02-smoke.sh` | Version string, help, env output |
| `03-dependencies.sh` | Static linking verification (`ldd`/`otool`/Windows equivalent) |
| `04-functionality.sh` | create, lint, template, package, show, pull, repo ops, plugins |
| `05-v4-features.sh` | v4-specific feature tests that don't need a cluster |
| `06-distribution.sh` | Archive extraction: `.tar.gz`, `.zip` |

**`scripts/binary/cluster/`** — require a live Kubernetes cluster (self-skip when absent):

| Script | Category |
|---|---|
| `01-functionality.sh` | install, status, upgrade, rollback, uninstall |
| `02-oci.sh` | OCI push (to `ttl.sh`), install from OCI, install by digest |
| `03-v4-features.sh` | v4-specific feature tests that require a cluster |

**`scripts/container/`** — container image checks (separate Tekton pipeline, not binary tests):

| Script | What it checks |
|---|---|
| `01-image-checks.sh` | Image labels (`name`, `version`, `release`, stream `cpe`), entrypoint binary presence, `helm version` output |
| `02-non-cluster-suite.sh` | Runs `scripts/binary/non-cluster/` against the container's `/usr/local/bin/helm` — non-cluster only; cluster-based container tests are a separate future effort |

Add new test cases inside the matching script, following the existing `pass "name"` / `fail "name" "detail"` / `skip "name" "reason"` pattern from `common.sh`. A genuinely new *category* in `binary/` is rare — prefer extending an existing script. If you do add one, place it in the correct subfolder (`non-cluster/` or `cluster/`) and wire it into both `.github/workflows/test-binary.yml` and the matching `.tekton/` pipeline. Workflow files are off-limits to fullsend agents — include a "Human action required — CI wiring" note in the PR description.

## Running tests locally

```shell
export BINARY_IMAGE="quay.io/redhat-user-workloads/helm-cli-tenant/helm-cli@sha256:<image-sha>"
source scripts/common.sh
./scripts/binary/non-cluster/01-validation.sh
```

Set `VERBOSE=1` to see the underlying commands and their output. `HELM_PLATFORM` overrides platform autodetection (useful for cross-checking a script against a platform you're not currently on); `HELM_BIN` overrides the binary path.

## fullsend agents

This repo runs [fullsend](https://fullsend.sh) in per-repo installation mode. Six agent roles operate automatically against issues and PRs here: `triage`, `coder` (its GitHub App/agent is named `code`, not `coder` — a naming quirk to know about), `review`, `fix`, `retro`, `prioritize`. Config and model pins live in `.fullsend/config.yaml` — treat that file as the source of truth for which model each role runs on; don't duplicate the values here, they will drift.

### Never touch `.github/workflows/*`

The `coder`/`fix` agents run under a GitHub App that does **not** have the `workflows` permission scope. If a generated commit modifies anything under `.github/workflows/`, GitHub hard-rejects the push at the git level — not a soft warning, the *entire* commit (all files in it) fails to push, even the unrelated changes riding along with it. This already happened once (issue #1: agent correctly wrote a helm-lint test but also touched `.github/workflows/test-binary.yml`, and the whole push got rejected).

When writing or triaging an issue meant for the `code` agent, be explicit that workflow files are off-limits: "do not modify anything under `.github/workflows/`." If a task genuinely requires a workflow change, that has to be done by a human directly, not delegated to the agent.

### Treat `.tekton/*` as sensitive too

Any file under `.tekton/` (currently `helm-prerelease-tests-pipeline.yaml` and `helm-container-tests-pipeline.yaml`) isn't blocked by GitHub the way workflow files are, but it's just as high-blast-radius if an agent gets it wrong. Scope issues to avoid it unless a human is going to review that specific diff closely.

### Treat `*-plan.md` files as human-managed too

`*-plan.md` and `*-integration-plan.md` files document human decisions about future work. Do not modify them unless the issue explicitly asks for it. If a glob pattern or file reference in such a document appears to be stale relative to your changes, note it in the PR description rather than editing the document.

### How the pipeline actually triggers

- `triage`: fires automatically on issue opened/edited, or manually via `/fs-triage` comment.
- `code`: fires on the `ready-to-code` label, or manually via `/fs-code` comment — does **not** require triage to have run first.
- `review`: fires automatically when the agent (or anyone) pushes to a PR; read-only, can't push code itself.
- `fix`: fires when review requests changes, or manually via `/fs-fix`; stop it mid-loop with `/fs-fix-stop`.
- `retro` / `prioritize`: on-demand via their own `/fs-*` commands, not part of the core code→review→fix loop.

Plain comments do nothing — only comments starting with `/fs-` route anywhere.

### No auto-merge — this is intentional

fullsend has no merge-automation feature at all. `ready-for-merge` is just a label the review agents apply; a human always has to click merge. Don't build around an assumption that a passing review means it's already merged.

### What the `code` agent can't verify itself

The sandbox the `code` agent runs in implementing a fix has **no network access** and doesn't run this repo's real multi-platform binary test matrix. It writes code, runs local tests/lint it has access to, then pushes — the actual verification of a fix happens in this repo's existing "Helm Binary Tests" CI workflow running on the resulting PR like any other PR. If that workflow fails, the `fix` agent reads its logs and iterates; a human should still glance at the real CI result before merging, not just the agent's own summary.

## Working conventions

- Test scripts must stay portable across bash on Linux/macOS and Git Bash on Windows (see the `CURRENT_OS`/`CHECKSUM_CMD`/`DEP_CHECK_CMD` branching in `common.sh`) — don't add Linux-only syntax to a script that also runs on Windows/macOS in CI.
- Don't hardcode a binary path or platform string; use `$HELM_BIN` / `$PLATFORM` / `$CURRENT_OS` from `common.sh`.
- `common.sh` already isolates `HELM_CONFIG_HOME`/`HELM_CACHE_HOME`/`HELM_DATA_HOME` per run and cleans them up on exit — new tests should rely on that isolation rather than touching the real Helm home.
- A CI/Konflux platform-coverage change (adding or removing a platform) touches `.github/workflows/test-binary.yml` and/or `.tekton/*` — both are off-limits to automated agents (see above), so scope those tasks for a human.
- **Assertions must be falsifiable.** Before committing a `pass`/`fail` check, ask: "Would this test still PASS if helm completely ignored the behavior under test?" If yes, the assertion is too weak. Specific patterns: (a) for negative tests expecting `helm lint` to fail, assert on `"1 chart(s) failed"` rather than generic words like `"error"` or `"failed"` that appear in success-path output too; (b) for warning-mode tests (`--strict`), verify the chart actually triggers the warning before expecting it — `helm create` does not generate `icon:`, `deprecated:`, or other optional fields.
- **Guard setup steps.** If a test section starts with `helm create` or similar setup, wrap the test body in a guard: `if run_cmd helm create ... && test -d "$chart"; then ... else skip "name" "helm create failed"; fi`. A silently-failed setup will otherwise cause the subsequent `helm lint` to emit `"1 chart(s) failed"` even for tests designed to expect success, producing a spurious FAIL — or for negative tests, a spurious PASS.
