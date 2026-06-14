#!/usr/bin/env bash
# Validation tests: checksums, file type, architecture match, binary size.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo ""
echo "=== 01: VALIDATION ==="
echo ""

# ---------------------------------------------------------------------------
# Checksum verification
# ---------------------------------------------------------------------------
if [[ -f "sha256sum.txt" ]]; then
    case "$CURRENT_OS" in
        linux)
            if sha256sum -c sha256sum.txt --quiet 2>/dev/null; then
                pass "Checksum verification"
            else
                fail "Checksum verification" "sha256sum -c failed"
            fi
            ;;
        darwin)
            all_ok=true
            while IFS= read -r line; do
                expected_hash="$(echo "$line" | awk '{print $1}')"
                filename="$(echo "$line" | awk '{print $2}')"
                filename="${filename#\*}"
                [[ -f "$filename" ]] || continue
                actual_hash="$(shasum -a 256 "$filename" | awk '{print $1}')"
                if [[ "$expected_hash" != "$actual_hash" ]]; then
                    all_ok=false
                    echo "  MISMATCH: $filename"
                fi
            done < sha256sum.txt
            if $all_ok; then
                pass "Checksum verification"
            else
                fail "Checksum verification" "one or more checksums did not match"
            fi
            ;;
        windows)
            all_ok=true
            while IFS= read -r line; do
                expected_hash="$(echo "$line" | awk '{print $1}')"
                filename="$(echo "$line" | awk '{print $2}')"
                filename="${filename#\*}"
                [[ -f "$filename" ]] || continue
                actual_hash="$(certutil -hashfile "$filename" SHA256 2>/dev/null | sed -n '2p' | tr -d ' ')"
                if [[ "${expected_hash,,}" != "${actual_hash,,}" ]]; then
                    all_ok=false
                    echo "  MISMATCH: $filename"
                fi
            done < sha256sum.txt
            if $all_ok; then
                pass "Checksum verification"
            else
                fail "Checksum verification" "one or more checksums did not match"
            fi
            ;;
    esac
else
    fail "Checksum verification" "sha256sum.txt not found"
fi

# ---------------------------------------------------------------------------
# File type check
# ---------------------------------------------------------------------------
if command -v file &>/dev/null; then
    file_output="$(file "$HELM_BIN")"
    case "$CURRENT_OS" in
        linux)
            if echo "$file_output" | grep -q "ELF 64-bit"; then
                pass "File type check"
            else
                fail "File type check" "expected ELF 64-bit, got: $file_output"
            fi
            ;;
        darwin)
            if echo "$file_output" | grep -q "Mach-O"; then
                pass "File type check"
            else
                fail "File type check" "expected Mach-O, got: $file_output"
            fi
            ;;
        windows)
            if echo "$file_output" | grep -q "PE32+"; then
                pass "File type check"
            else
                fail "File type check" "expected PE32+, got: $file_output"
            fi
            ;;
    esac
else
    skip "File type check" "file command not available"
fi

# ---------------------------------------------------------------------------
# Architecture match
# ---------------------------------------------------------------------------
if command -v file &>/dev/null; then
    file_output="$(file "$HELM_BIN")"
    arch_ok=false
    case "$GOARCH" in
        amd64)
            echo "$file_output" | grep -qiE "x86.64|x86_64|AMD64" && arch_ok=true
            ;;
        arm64)
            echo "$file_output" | grep -qiE "arm64|aarch64|ARM64" && arch_ok=true
            ;;
        ppc64le)
            echo "$file_output" | grep -qi "ppc64" && arch_ok=true
            ;;
        s390x)
            echo "$file_output" | grep -qi "s390" && arch_ok=true
            ;;
    esac
    if $arch_ok; then
        pass "Architecture match"
    else
        fail "Architecture match" "expected ${GOARCH} in: $file_output"
    fi
else
    skip "Architecture match" "file command not available"
fi

# ---------------------------------------------------------------------------
# Permissions check
# ---------------------------------------------------------------------------
if [[ "$CURRENT_OS" == "windows" ]]; then
    if [[ -f "$HELM_BIN" ]]; then
        pass "Check permissions (windows — no executable bit)"
    else
        fail "Check permissions" "binary not found: $HELM_BIN"
    fi
else
    if [[ -x "$HELM_BIN" ]]; then
        perms="$(stat -c "%a" "$HELM_BIN" 2>/dev/null || stat -f "%Lp" "$HELM_BIN" 2>/dev/null)"
        pass "Check permissions (${perms})"
    else
        fail "Check permissions" "binary is not executable: $HELM_BIN"
    fi
fi

# ---------------------------------------------------------------------------
# Binary size check (expect 40-80 MB)
# ---------------------------------------------------------------------------
if [[ -f "$HELM_BIN" ]]; then
    size_bytes="$(wc -c < "$HELM_BIN" | tr -d ' ')"
    size_mb=$((size_bytes / 1024 / 1024))
    if [[ $size_mb -ge 40 ]] && [[ $size_mb -le 80 ]]; then
        pass "Binary size check (${size_mb}MB)"
    else
        fail "Binary size check" "expected 40-80MB, got ${size_mb}MB"
    fi
else
    fail "Binary size check" "binary not found: $HELM_BIN"
fi

summary
