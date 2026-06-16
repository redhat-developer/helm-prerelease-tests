#!/usr/bin/env bash
# Distribution tests: extract .tar.gz archives for all platforms.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo ""
echo "=== 09: DISTRIBUTION ==="
echo ""

# ---------------------------------------------------------------------------
# .tar.gz extraction — test all available platform archives
# ---------------------------------------------------------------------------
tgz_found=false
for archive in helm-linux-*.tar.gz helm-darwin-*.tar.gz helm-windows-*.tar.gz; do
    [[ -f "$archive" ]] || continue
    tgz_found=true
    extract_dir="test-extract-$(basename "$archive" .tar.gz)"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"

    if tar -xzf "$archive" -C "$extract_dir" 2>/dev/null; then
        binary_name="$(basename "$archive" .tar.gz)"
        # Windows binaries have .exe inside the archive
        if [[ -f "${extract_dir}/${binary_name}" ]]; then
            extracted="${extract_dir}/${binary_name}"
        elif [[ -f "${extract_dir}/${binary_name}.exe" ]]; then
            extracted="${extract_dir}/${binary_name}.exe"
        else
            fail "Extract ${archive}" "no binary found in archive"
            rm -rf "$extract_dir"
            continue
        fi

        if command -v file &>/dev/null; then
            file_out="$(file "$extracted")"
            log_captured "file $extracted" "$file_out"
            if echo "$file_out" | grep -qiE "ELF|Mach-O|PE32+"; then
                pass "Extract ${archive}"
            else
                fail "Extract ${archive}" "unexpected file type: $file_out"
            fi
        else
            pass "Extract ${archive}"
        fi
    else
        fail "Extract ${archive}" "tar extraction failed"
    fi
    rm -rf "$extract_dir"
done

if ! $tgz_found; then
    skip "Extract .tar.gz archives" "no .tar.gz archives found"
fi

summary
