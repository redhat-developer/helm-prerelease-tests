#!/usr/bin/env bash
# Distribution tests: extract .tar.gz and .zip archives, verify contents.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo ""
echo "=== 09: DISTRIBUTION ==="
echo ""

# ---------------------------------------------------------------------------
# .tar.gz extraction — test all available platform archives
# ---------------------------------------------------------------------------
tgz_found=false
for archive in helm-linux-*.tar.gz helm-darwin-*.tar.gz; do
    [[ -f "$archive" ]] || continue
    tgz_found=true
    extract_dir="test-extract-$(basename "$archive" .tar.gz)"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"

    if tar -xzf "$archive" -C "$extract_dir" 2>/dev/null; then
        binary_name="$(basename "$archive" .tar.gz)"
        if [[ -f "${extract_dir}/${binary_name}" ]]; then
            if command -v file &>/dev/null; then
                file_out="$(file "${extract_dir}/${binary_name}")"
                log_captured "file ${extract_dir}/${binary_name}" "$file_out"
                if echo "$file_out" | grep -qiE "ELF|Mach-O"; then
                    pass "Extract ${archive}"
                else
                    fail "Extract ${archive}" "unexpected file type: $file_out"
                fi
            else
                pass "Extract ${archive}"
            fi
        else
            fail "Extract ${archive}" "binary ${binary_name} not found in archive"
        fi
    else
        fail "Extract ${archive}" "tar extraction failed"
    fi
    rm -rf "$extract_dir"
done

if ! $tgz_found; then
    skip "Extract .tar.gz archives" "no .tar.gz archives found"
fi

# ---------------------------------------------------------------------------
# .zip extraction — windows archives
# ---------------------------------------------------------------------------
zip_found=false
if ! command -v unzip &>/dev/null; then
    skip "Extract .zip archives" "unzip not installed"
else
for archive in helm-windows-*.exe.zip; do
    [[ -f "$archive" ]] || continue
    zip_found=true
    extract_dir="test-extract-$(basename "$archive" .zip)"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"

    if unzip -q "$archive" -d "$extract_dir" 2>/dev/null; then
        exe_name="$(basename "$archive" .zip)"
        if [[ -f "${extract_dir}/${exe_name}" ]]; then
            if command -v file &>/dev/null; then
                file_out="$(file "${extract_dir}/${exe_name}")"
                log_captured "file ${extract_dir}/${exe_name}" "$file_out"
                if echo "$file_out" | grep -qi "PE32+"; then
                    pass "Extract ${archive}"
                else
                    fail "Extract ${archive}" "unexpected file type: $file_out"
                fi
            else
                pass "Extract ${archive}"
            fi
        else
            fail "Extract ${archive}" "exe ${exe_name} not found in archive"
        fi
    else
        fail "Extract ${archive}" "unzip failed"
    fi
    rm -rf "$extract_dir"
done

if ! $zip_found; then
    if [[ "$CURRENT_OS" == "windows" ]]; then
        fail "Extract .zip archives" "no .zip archives found on windows"
    else
        skip "Extract .zip archives" "no .zip archives found (expected on non-windows)"
    fi
fi
fi

summary
