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
# A FIPS-enabled build embeds a GOFIPS140=v1.0.0-<hash> stamp as printable
# text. grep -a treats the binary as text; -F matches fixed strings.
# This is the check that would have caught 3.21.2.1-83.
if grep -qaF 'GOFIPS140' "$HELM_BIN"; then
    pass "fips-build-stamp-present"
else
    fail "fips-build-stamp-present" "binary contains no GOFIPS140 build stamp"
fi

# ---------------------------------------------------------------------------
# 2. Build tag — -tags=...,fips140v1.0
# ---------------------------------------------------------------------------
if grep -qaF 'fips140v1.0' "$HELM_BIN"; then
    pass "fips-build-tag"
else
    fail "fips-build-tag" "expected fips140v1.0 build tag not found"
fi

# ---------------------------------------------------------------------------
# 3. DefaultGODEBUG — fips140=auto
# ---------------------------------------------------------------------------
if grep -qaF 'fips140=auto' "$HELM_BIN"; then
    pass "fips-default-godebug"
else
    fail "fips-default-godebug" "expected DefaultGODEBUG fips140=auto not found"
fi

# ---------------------------------------------------------------------------
# 4. Non-FIPS host behavior — ChaCha20-Poly1305 acceptance
# ---------------------------------------------------------------------------
# On a non-FIPS host, helm must accept a TLS connection offering only
# ChaCha20-Poly1305 (a non-FIPS cipher). This confirms FIPS activation
# is host-conditional (fips140=auto) rather than stuck on.
#
# Constraints (from debugging history):
#   - The server must disable HTTP/2 (TLSNextProto). HTTP/2 requires
#     AES-GCM and refuses to start on a ChaCha20-only config.
#   - OpenSSL s_server is not a substitute — a FIPS host's provider
#     will not offer ChaCha20.
#
# Needs a Go toolchain to build the probe server.
# Skips on FIPS-enabled hosts — non-FIPS behavior is not testable there.

chacha_skip=""
if test -f /proc/sys/crypto/fips_enabled; then
    fips_val="$(cat /proc/sys/crypto/fips_enabled)"
    if test "$fips_val" = "1"; then
        chacha_skip="host is FIPS-enabled — non-FIPS behavior not testable here"
    fi
fi

if test -n "$chacha_skip"; then
    skip "non-fips-chacha20" "$chacha_skip"
elif ! command -v go >/dev/null 2>&1; then
    skip "non-fips-chacha20" "Go toolchain absent"
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
		// Disable HTTP/2 — it requires AES-GCM and refuses to start
		// on a ChaCha20-only config.
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

    if ! test -x "${probe_dir}/probe"; then
        skip "non-fips-chacha20" "probe failed to compile: ${build_err}"
        rm -rf "$probe_dir"
    else
        # Start the server and wait for it to print its listener address.
        "${probe_dir}/probe" > "${probe_dir}/addr" 2>"${probe_dir}/srv.err" &
        probe_pid=$!

        addr=""
        for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            if test -s "${probe_dir}/addr"; then
                addr="$(head -1 "${probe_dir}/addr" | tr -d '\r\n')"
                break
            fi
            sleep 0.5
        done

        if test -z "$addr"; then
            skip "non-fips-chacha20" \
                "probe server did not start: $(cat "${probe_dir}/srv.err" 2>/dev/null)"
            kill "$probe_pid" 2>/dev/null || true
            wait "$probe_pid" 2>/dev/null || true
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

            # A TLS cipher/handshake error means FIPS blocked ChaCha20
            # even though the host is non-FIPS — stuck on.
            # Any other outcome (e.g. "not a valid chart repository")
            # means the handshake succeeded — correct behavior.
            if echo "$helm_output" | grep -qi "cipher\|handshake failure"; then
                fail "non-fips-chacha20" \
                    "ChaCha20 rejected on non-FIPS host — FIPS appears stuck on"
            else
                pass "non-fips-chacha20"
            fi
        fi

        rm -rf "$probe_dir"
    fi
fi

summary
