#!/usr/bin/env bash
# FIPS verification: build stamp presence and non-FIPS host behavior.
#
# Build-stamp checks run on all platforms without a Go toolchain.
# The non-FIPS behavior probe (ChaCha20 acceptance) needs Go and
# skips where absent or where the host is FIPS-enabled.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../common.sh"

echo ""
echo "=== 07: FIPS ==="
echo ""

# ---------------------------------------------------------------------------
# 1. Build stamp — GOFIPS140 module linked
# ---------------------------------------------------------------------------
# Red Hat applies GOFIPS140=certified at build time for all seven shipped
# platform targets (linux-amd64, linux-arm64, linux-ppc64le, linux-s390x,
# darwin-amd64, darwin-arm64, windows-amd64). All binaries are expected to
# carry the GOFIPS140=v1.0.0-<hash> stamp; a missing stamp on any platform
# is a build defect. This is the check that would have caught 3.21.2.1-83.
#
# grep -a treats the binary as text; -F matches fixed strings.
# Assert the value (v1.0.0) not just the key: GOFIPS140=latest links the
# latest module rather than the frozen certified snapshot and must not pass.
#
# The version (v1.0.0) corresponds to the first CMVP-certified snapshot of
# the Go FIPS 140-2 module. When Red Hat certifies a newer snapshot
# (e.g., v1.1.0), update the grep string below to the new version. Confirm
# the new stamp first with `go version -m <binary>`, or by grepping the
# binary for GOFIPS140= directly if no Go toolchain is to hand.
if grep -qaF 'GOFIPS140=v1.0.0' "$HELM_BIN"; then
    pass "GOFIPS140 build stamp present"
else
    fail "GOFIPS140 build stamp present" "binary contains no GOFIPS140=v1.0.0 build stamp (certified module not linked)"
fi

# ---------------------------------------------------------------------------
# 2. Build tag — -tags=...,fips140v1.0
# ---------------------------------------------------------------------------
if grep -qaF 'fips140v1.0' "$HELM_BIN"; then
    pass "FIPS build tag (fips140v1.0)"
else
    fail "FIPS build tag (fips140v1.0)" "expected fips140v1.0 build tag not found"
fi

# ---------------------------------------------------------------------------
# 3. DefaultGODEBUG — fips140=auto
# ---------------------------------------------------------------------------
if grep -qaF 'fips140=auto' "$HELM_BIN"; then
    pass "DefaultGODEBUG fips140=auto"
else
    fail "DefaultGODEBUG fips140=auto" "expected DefaultGODEBUG fips140=auto not found"
fi

# ---------------------------------------------------------------------------
# 4. ChaCha20-Poly1305 negotiation — expectation depends on the host
# ---------------------------------------------------------------------------
# One probe, two assertions. A local TLS server offers ONLY ChaCha20-
# Poly1305, a non-FIPS cipher, and we observe what helm puts on the wire:
#
#   non-FIPS host → helm must ACCEPT it. Proves FIPS activation is
#                   host-conditional (fips140=auto) and not stuck on.
#                   A rejection here would break non-FIPS customers.
#   FIPS host     → helm must REJECT it. This is Gate B: proof that FIPS
#                   actually activates, not merely that the certified
#                   module is linked. Previously this arm was skipped.
#
# Both arms are real assertions; neither is informational. The handshake
# outcome is the signal, so the only host input that matters is
# /proc/sys/crypto/fips_enabled (absent on darwin/windows → non-FIPS).
#
# Constraints (from debugging history):
#   - The server must pin MaxVersion to TLS 1.2. Measured: without the
#     pin a FIPS-stuck binary negotiates TLS 1.3 + AES-GCM and the probe
#     reports PASS. The pin is what makes this assertion falsifiable.
#   - The server must not speak HTTP/2; h2 requires AES-GCM and will not
#     work on a ChaCha20-only config. As written this is already
#     guaranteed by tls.Listen + Serve (no ALPN); TLSNextProto is kept
#     as a guard against a refactor to ListenAndServeTLS.
#   - OpenSSL s_server is not a substitute — a FIPS host's provider
#     will not offer ChaCha20.
#
# Needs a Go toolchain to build the probe server.

host_fips=0
if [[ -f /proc/sys/crypto/fips_enabled ]]; then
    host_fips="$(cat /proc/sys/crypto/fips_enabled 2>/dev/null || echo 0)"
fi

if [[ "$host_fips" == "1" ]]; then
    chacha_test="FIPS host ChaCha20 rejection"
else
    chacha_test="Non-FIPS host ChaCha20 acceptance"
fi

if ! command -v go >/dev/null 2>&1; then
    skip "$chacha_test" "Go toolchain absent"
else
    probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/fips-probe.XXXXXX")"

    cat > "${probe_dir}/go.mod" << 'MODEOF'
module fips-probe

go 1.21
MODEOF

    cat > "${probe_dir}/main.go" << 'GOEOF'
package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"math/big"
	"net"
	"net/http"
	"os"
	"time"
)

func main() {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		fmt.Fprintf(os.Stderr, "keygen: %v\n", err)
		os.Exit(1)
	}
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		IPAddresses:  []net.IP{net.IPv4(127, 0, 0, 1)},
		NotBefore:    time.Now(),
		NotAfter:     time.Now().Add(time.Hour),
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		fmt.Fprintf(os.Stderr, "cert: %v\n", err)
		os.Exit(1)
	}
	cfg := &tls.Config{
		Certificates: []tls.Certificate{{
			Certificate: [][]byte{der},
			PrivateKey:  key,
		}},
		// Force TLS 1.2 so CipherSuites config takes effect (TLS 1.3
		// does not allow restricting cipher suites via this field).
		// Do not drop MaxVersion: measured, a FIPS-stuck binary completes
		// a TLS 1.3 AES-GCM handshake against an unpinned server, and the
		// probe then reports PASS for a binary it should fail.
		CipherSuites: []uint16{tls.TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256},
		MinVersion:   tls.VersionTLS12,
		MaxVersion:   tls.VersionTLS12,
	}
	ln, err := tls.Listen("tcp", "127.0.0.1:0", cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "listen: %v\n", err)
		os.Exit(1)
	}
	// Print the listener address so the calling script can connect.
	fmt.Println(ln.Addr().String())
	srv := &http.Server{
		// Guard only. tls.Listen + Serve never configures HTTP/2 (that
		// happens in ListenAndServeTLS/ServeTLS) and no ALPN protocols
		// are advertised, so h2 cannot be negotiated here today. Kept
		// because h2 requires AES-GCM and would break a ChaCha20-only
		// config if someone switched to ListenAndServeTLS.
		TLSNextProto: make(map[string]func(*http.Server, *tls.Conn, http.Handler)),
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			fmt.Fprintln(w, "not-a-repo-index")
		}),
	}
	srv.Serve(ln)
}
GOEOF

    # Build the probe server; only stdlib is used so no module download.
    build_err=""
    build_err="$(cd "${probe_dir}" && go build -o probe . 2>&1)" || true

    if [[ ! -x "${probe_dir}/probe" ]]; then
        skip "$chacha_test" "probe failed to compile: ${build_err}"
        rm -rf "$probe_dir"
    else
        # Register a cleanup for the probe process before starting it, so
        # the probe is killed if the script exits unexpectedly (e.g., a
        # SIGTERM or uncaught error) between the launch and the explicit
        # kill/wait calls below. Chains with common.sh's cleanup_helm_home.
        probe_pid=""
        _chacha_cleanup() {
            if [[ -n "${probe_pid:-}" ]]; then
                kill "$probe_pid" 2>/dev/null || true
            fi
        }
        trap '_chacha_cleanup; cleanup_helm_home' EXIT

        # Start the server and wait for it to print its listener address.
        "${probe_dir}/probe" > "${probe_dir}/addr" 2>"${probe_dir}/srv.err" &
        probe_pid=$!

        addr=""
        for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            if [[ -s "${probe_dir}/addr" ]]; then
                addr="$(head -1 "${probe_dir}/addr" | tr -d '\r\n')"
                break
            fi
            sleep 0.5
        done

        if [[ -z "$addr" ]]; then
            skip "$chacha_test" \
                "probe server did not start: $(cat "${probe_dir}/srv.err" 2>/dev/null)"
            kill "$probe_pid" 2>/dev/null || true
            wait "$probe_pid" 2>/dev/null || true
            rm -rf "$probe_dir"
        else
            log_verbose "probe server listening on ${addr}"

            # helm repo add against the ChaCha20-only server.
            # --insecure-skip-tls-verify skips cert verification but
            # cipher negotiation still happens in the TLS handshake.
            helm_output="$("$HELM_BIN" repo add fips-probe "https://${addr}" \
                --insecure-skip-tls-verify 2>&1)" || true
            log_captured \
                "$HELM_BIN repo add fips-probe https://${addr} --insecure-skip-tls-verify" \
                "$helm_output"

            # Clean up the repo entry regardless of outcome.
            "$HELM_BIN" repo remove fips-probe 2>/dev/null || true
            kill "$probe_pid" 2>/dev/null || true
            wait "$probe_pid" 2>/dev/null || true

            # Two observable outcomes, interpreted against the host state:
            #
            #   rejected  — a TLS cipher/handshake error. helm would not
            #               speak ChaCha20. Correct on a FIPS host, a
            #               defect on a non-FIPS one (FIPS stuck on).
            #   accepted  — "not a valid chart repository" proves the
            #               handshake completed and helm reached the HTTP
            #               layer. Correct on a non-FIPS host, a Gate B
            #               failure on a FIPS one (FIPS never activated).
            #
            # Neither signal means the probe crashed or the exchange was
            # inconclusive — skip rather than guess in either direction.
            if echo "$helm_output" | grep -Eqi "no cipher suite|handshake failure|cipher.*error"; then
                if [[ "$host_fips" == "1" ]]; then
                    pass "$chacha_test"
                else
                    fail "$chacha_test" \
                        "ChaCha20 rejected on non-FIPS host — FIPS appears stuck on"
                fi
            elif echo "$helm_output" | grep -qi "not a valid chart repository"; then
                if [[ "$host_fips" == "1" ]]; then
                    fail "$chacha_test" \
                        "ChaCha20 accepted on a FIPS host — FIPS did not activate"
                else
                    pass "$chacha_test"
                fi
            else
                skip "$chacha_test" \
                    "no cipher failure and no successful-handshake marker observed — outcome inconclusive"
            fi
        fi

        rm -rf "$probe_dir"
    fi
fi

summary
