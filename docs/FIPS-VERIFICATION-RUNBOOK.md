# FIPS Verification Runbook

Methodology and reference for verifying FIPS compliance in Red Hat's downstream
Helm CLI builds.

## Why FIPS matters for the downstream fork

The downstream build sets `GODEBUG fips140=auto`, `CGO_ENABLED=0` and static
linking, and links the frozen CMVP-certified module via `GOFIPS140=certified`.
Three mechanisms get conflated:

| Mechanism | What it does | Build stamp produced |
|---|---|---|
| `godebug fips140=auto` in `go.mod` | Compiled-in default GODEBUG; host-conditional activation | `DefaultGODEBUG=fips140=auto` — **no module selected** |
| `GODEBUG=fips140=auto go build` | Env var for the `go` process only | **nothing** |
| `GOFIPS140=certified` at build time | Links the frozen certified module snapshot | `GOFIPS140=v1.0.0-...` + `-tags=fips140v1.0` — **what check-payload reads** |

Both `GOFIPS140=certified` and `fips140=auto` are Red Hat fork only; upstream Go
rejects `certified` at build time and panics at init on `auto`.

## Two independent gates

|  | Gate A — build stamp | Gate B — runtime behavior |
|---|---|---|
| Question | Is the certified crypto module linked? | Does FIPS activate on a FIPS host? |
| Needs a FIPS machine? | No | Yes |
| Cost | Seconds | ~30 min incl. provisioning |
| Automated check | `scripts/binary/non-cluster/07-fips.sh` (stamp checks) | `plans/fips.fmf` on a FIPS-enabled Testing Farm guest |

**Passing one says nothing about the other.** In August 2026, helm `3.21.2.1-83`
passed Gate B (behavioral testing on a FIPS host) and shipped, then was rejected
by `check-payload` for failing Gate A (no GOFIPS140 build stamp).

### Gate A — build stamp verification

Expected stamps in a correctly built binary:

```
build  -tags=no_openssl,fips140v1.0
build  DefaultGODEBUG=fips140=auto
build  GOFIPS140=v1.0.0-c2097c7c
```

`go version -m <binary>` reads these but needs a Go toolchain, which most runners
lack. The stamps are embedded in the binary as printable text and are readable
with `grep -aF` — no toolchain required. This is the approach used in
`07-fips.sh` so it runs on all seven platforms.

Three checks:
1. **`GOFIPS140`** — the certified module is linked.
2. **`fips140v1.0`** — the build tag is present.
3. **`fips140=auto`** — the DefaultGODEBUG is set for host-conditional activation.

### Gate B — runtime behavior (non-FIPS host)

On a non-FIPS host, FIPS mode should be inactive and helm should accept
ChaCha20-Poly1305 (a non-FIPS cipher). If it rejects ChaCha20 on a non-FIPS
host, FIPS activation is stuck on rather than host-conditional — a real defect.

The probe is a Go TLS server offering only `TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256`:
- Forces TLS 1.2 (`MaxVersion: tls.VersionTLS12`) so `CipherSuites` config applies.
- Disables HTTP/2 (`TLSNextProto`). HTTP/2 requires AES-GCM and refuses to start
  on a ChaCha20-only config — without this you get "connection refused" on both
  arms and a meaningless result.
- Uses a self-signed ECDSA cert; helm's `--insecure-skip-tls-verify` skips cert
  verification but cipher negotiation still happens.

| Host | ChaCha20 must be | Signal |
|---|---|---|
| FIPS | **rejected** | TLS handshake fails: `tls: no cipher suite supported by both client and server` |
| non-FIPS | **accepted** | Handshake succeeds; helm then fails parsing the response as a repo index |

The non-FIPS arm matters on its own: stuck-on FIPS would be a real defect, and a
FIPS host cannot distinguish "correctly auto-on" from "always-on."

**Why not OpenSSL `s_server`?** A FIPS host's OpenSSL provider will not offer
ChaCha20, so the probe cannot be built with it. The Go probe uses the standard
library and does not depend on the host's OpenSSL configuration.

## Known non-defects

Do not code these as test failures:

- **`GODEBUG=fips140=only` failing against `charts.helm.sh`:**
  `crypto/ecdh: use of X25519 is not allowed in FIPS 140-only mode`. That is the
  *endpoint's* curve choice, identical on FIPS-good and FIPS-broken builds. On
  certified-module builds it now succeeds. Informational either way.

- **Under `fips140=only` the ChaCha20 probe trips at key exchange (X25519) before
  cipher selection is reached.** Conclusion unchanged; only the stage differs.

## Running the checks

### Build stamp (all platforms, no prerequisites)

```bash
export BINARY_IMAGE="quay.io/redhat-user-workloads/helm-cli-tenant/helm-cli@sha256:<digest>"
source scripts/common.sh
./scripts/binary/non-cluster/07-fips.sh
```

### ChaCha20 probe (requires Go toolchain)

Same invocation — `07-fips.sh` detects Go automatically and skips the probe
if absent. Set `VERBOSE=1` for full output including the probe server address:

```bash
VERBOSE=1 ./scripts/binary/non-cluster/07-fips.sh
```

### FIPS-enabled guest (Testing Farm)

The `plans/fips.fmf` plan enables FIPS on the guest via tmt's `feature` plugin,
verifies FIPS is active, then runs the non-cluster suite. Use it via a Testing
Farm IntegrationTestScenario with `TMT_PLAN=/fips`.

## Results history

| Build | Gate A (stamp) | Gate B (non-FIPS host) | Notes |
|---|---|---|---|
| `3.21.2.1-83` | **FAIL** | PASS | Shipped; rejected by `check-payload` — no GOFIPS140 stamp |

Update this table as new builds are verified.
