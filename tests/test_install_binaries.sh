#!/usr/bin/env bash
# Behavioural tests for scripts/install/install_binaries.sh
# (local fixtures, all URLs are file://, no network).
#
# Covers:
#   - --dry-run changes nothing
#   - downloads disabled: missing targets -> exit 3
#   - first run installs every kind, verified by sha256, via the cache
#   - the cache serves installs offline; deleted files come back
#   - a wrong checksum is refused (exit 1, no partial files in the cache)
#   - an existing regular file is never replaced by a link
#   - the real manifest (config/binaries.tsv) is well formed
#   - a half-installed sdk is replaced, not nested
#   - rows with a wrong option are rejected, naming the row
#   - env_vars exposes the sdk go when the system has no go

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

# test_helper.sh has no executable-file assertion
assert_executable() {
    local file="$1"
    local message="${2:-$file should be an executable file}"
    if [[ -f "$file" && -x "$file" ]]; then
        echo -e "${GREEN}✓${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

echo "========================================"
echo "Install Binaries Tests"
echo "========================================"
echo ""

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# --- fixtures (real tar and sha256) ---
mkdir -p "$T/fixtures"

mkdir -p "$T/fixtures/age-src/age"
printf '#!/bin/bash\necho age\n' > "$T/fixtures/age-src/age/age"
printf '#!/bin/bash\necho age-keygen\n' > "$T/fixtures/age-src/age/age-keygen"
chmod +x "$T/fixtures/age-src/age/age" "$T/fixtures/age-src/age/age-keygen"
tar -czf "$T/fixtures/age.tgz" -C "$T/fixtures/age-src" age

mkdir -p "$T/fixtures/go-src/go/bin"
printf '#!/bin/bash\necho go\n' > "$T/fixtures/go-src/go/bin/go"
chmod +x "$T/fixtures/go-src/go/bin/go"
tar -czf "$T/fixtures/go.tgz" -C "$T/fixtures/go-src" go

cat > "$T/fixtures/fake.appimage" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--appimage-extract" ]]; then
    mkdir -p squashfs-root/usr/bin
    printf '#!/bin/bash\necho nvim\n' > squashfs-root/usr/bin/nvim
    chmod +x squashfs-root/usr/bin/nvim
fi
exit 0
EOF
chmod +x "$T/fixtures/fake.appimage"

printf '#!/bin/bash\necho neofetch\n' > "$T/fixtures/neofetch"
chmod +x "$T/fixtures/neofetch"

AGE_SHA=$(sha256sum "$T/fixtures/age.tgz" | awk '{print $1}')
GO_SHA=$(sha256sum "$T/fixtures/go.tgz" | awk '{print $1}')
AP_SHA=$(sha256sum "$T/fixtures/fake.appimage" | awk '{print $1}')
NEO_SHA=$(sha256sum "$T/fixtures/neofetch" | awk '{print $1}')

write_manifest() {
    # the fixture manifest: five rows, four distinct downloads
    {
        printf 'sdk/go\tsdk\tfile://%s/fixtures/go.tgz\t%s\t-\n' "$T" "$GO_SHA"
        printf 'env/bin/age\ttarball\tfile://%s/fixtures/age.tgz\t%s\tage/age\n' "$T" "$AGE_SHA"
        printf 'env/bin/age-keygen\ttarball\tfile://%s/fixtures/age.tgz\t%s\tage/age-keygen\n' "$T" "$AGE_SHA"
        printf 'env/bin/AppImages/fake.appimage\tappimage\tfile://%s/fixtures/fake.appimage\t%s\textract=env/bin/fake-appimage\n' "$T" "$AP_SHA"
        printf 'env/bin/neofetch\tfile\tfile://%s/fixtures/neofetch\t%s\t-\n' "$T" "$NEO_SHA"
    } > "$T/manifest.tsv"
}
write_manifest

export BINARIES_MANIFEST="$T/manifest.tsv"
export BINARIES_CACHE="$T/cache"
export BINARIES_CURL="curl -fsSL"

run_installer() {
    # runs the real script with ENV_DIR=$T, output to $T/run.out
    ENV_DIR="$T" bash "$ENV_DIR/scripts/install/install_binaries.sh" "$@" \
        > "$T/run.out" 2>&1
}

# S1: --dry-run on the empty tree changes nothing
run_installer --dry-run
assert_exit_code 0 $? "S1: --dry-run must exit 0"
if [[ ! -e "$T/env" && ! -e "$T/sdk" && ! -e "$T/cache" ]]; then
    assert_equals "" "" "S1: dry-run created nothing"
else
    assert_equals "" "present: $(ls "$T")" "S1: dry-run must create nothing"
fi

# S2: downloads disabled -> missing targets, exit 3
BINARIES_NO_NETWORK=1 run_installer
assert_exit_code 3 $? "S2: downloads disabled must exit 3"
assert_file_not_exists "$T/env/bin/age" "S2: nothing installed when downloads disabled"

# link targets the links step can find (the others are intentionally absent)
mkdir -p "$T/env/scripts/tools" "$T/env/local/wemux"
touch "$T/env/scripts/tools/sysboard.sh"
chmod +x "$T/env/scripts/tools/sysboard.sh"
touch "$T/env/local/wemux/wemux"

# S3: first real run installs everything, verified, cached, linked
run_installer
assert_exit_code 0 $? "S3: first real run must exit 0"
assert_executable "$T/env/bin/age" "S3: age installed and executable"
assert_executable "$T/env/bin/age-keygen" "S3: age-keygen installed and executable"
assert_executable "$T/sdk/go/bin/go" "S3: go sdk installed and executable"
assert_executable "$T/env/bin/AppImages/fake.appimage" \
    "S3: appimage installed and executable"
assert_executable "$T/env/bin/fake-appimage/usr/bin/nvim" \
    "S3: extracted nvim is executable"
assert_executable "$T/env/bin/neofetch" "S3: neofetch installed and executable"
out=$("$T/env/bin/age-keygen")
assert_equals "age-keygen" "$out" "S3: age-keygen prints its own name"
n=$(find "$T/cache" -maxdepth 1 -type f | wc -l)
assert_equals "4" "$n" "S3: cache holds one sha256-named file per distinct download"
if [[ -L "$T/env/bin/sysboard" && \
        "$(readlink "$T/env/bin/sysboard")" == "../scripts/tools/sysboard.sh" ]]; then
    assert_equals "" "" "S3: bin/sysboard links to ../scripts/tools/sysboard.sh"
else
    assert_equals "../scripts/tools/sysboard.sh" \
        "$(readlink "$T/env/bin/sysboard" 2>/dev/null)" \
        "S3: bin/sysboard must link to ../scripts/tools/sysboard.sh"
fi
if [[ -L "$T/env/bin/wemux" && \
        "$(readlink "$T/env/bin/wemux")" == "../local/wemux/wemux" ]]; then
    assert_equals "" "" "S3: bin/wemux links to ../local/wemux/wemux"
else
    assert_equals "../local/wemux/wemux" \
        "$(readlink "$T/env/bin/wemux" 2>/dev/null)" \
        "S3: bin/wemux must link to ../local/wemux/wemux"
fi
assert_file_not_exists "$T/env/bin/nvim" \
    "S3: bin/nvim link not created (no nvim-appimage target)"
assert_file_not_exists "$T/env/bin/birch" \
    "S3: bin/birch link not created (no target)"

# S4: idempotent and offline - served from the cache
rm "$T/env/bin/age" "$T/env/bin/neofetch"
sed -E 's#file://[^[:space:]]+#file:///nonexistent#g' "$T/manifest.tsv" \
    > "$T/manifest.offline"
cp "$T/manifest.offline" "$T/manifest.tsv"
BINARIES_NO_NETWORK=1 run_installer
assert_exit_code 0 $? "S4: offline run served from cache must exit 0"
assert_file_exists "$T/env/bin/age" "S4: age restored from cache"
assert_file_exists "$T/env/bin/neofetch" "S4: neofetch restored from cache"

# S5: a wrong checksum is refused
printf 'env/bin/bad\tfile\tfile://%s/fixtures/neofetch\t%s\t-\n' \
    "$T" "$(printf '0%.0s' {1..64})" > "$T/manifest.tsv"
run_installer
assert_exit_code 1 $? "S5: wrong checksum must exit 1"
assert_file_not_exists "$T/env/bin/bad" "S5: mismatched artifact not installed"
parts=$(find "$T/cache" -maxdepth 1 -name '.part*' -print)
assert_equals "" "$parts" "S5: no partial files left in the cache"

# S6: an existing regular file is never replaced by a link
printf 'mine' > "$T/env/bin/wemux"
printf 'env/bin/neofetch\tfile\tfile://%s/fixtures/neofetch\t%s\t-\n' \
    "$T" "$NEO_SHA" > "$T/manifest.tsv"
run_installer
assert_exit_code 0 $? "S6: run with only the file row must exit 0"
if [[ -f "$T/env/bin/wemux" && ! -L "$T/env/bin/wemux" ]] \
        && [[ "$(cat "$T/env/bin/wemux")" == "mine" ]]; then
    assert_equals "" "" "S6: regular file never replaced by a link"
else
    assert_equals "mine" "$(cat "$T/env/bin/wemux" 2>/dev/null)" \
        "S6: wemux must stay a regular file containing 'mine'"
fi

# S7: the real manifest is well formed
manifest="$ENV_DIR/config/binaries.tsv"
assert_file_exists "$manifest" "S7: real manifest exists"
rows=$(grep -cve '^\s*$' -e '^\s*#' "$manifest")
assert_equals "6" "$rows" "S7: manifest has 6 data rows"
badcols=$(awk -F '\t' '!/^#/ && NF != 5' "$manifest" | wc -l)
assert_equals "0" "$badcols" "S7: every data row has 5 tab-separated columns"
badsha=$(awk -F '\t' '!/^#/ && $4 !~ /^[0-9a-f]{64}$/' "$manifest" | wc -l)
assert_equals "0" "$badsha" "S7: every sha256 is 64 lowercase hex characters"
badurl=$(awk -F '\t' '!/^#/ && $3 !~ /^https:\/\//' "$manifest" | wc -l)
assert_equals "0" "$badurl" "S7: every url starts with https://"

# S8: a half-installed sdk is replaced, not nested
rm -rf "$T/sdk/go"
mkdir -p "$T/sdk/go"
touch "$T/sdk/go/junk"
write_manifest
run_installer
assert_exit_code 0 $? "S8: run over a half-installed sdk must exit 0"
assert_executable "$T/sdk/go/bin/go" \
    "S8: go sdk reinstalled with a working bin/go"
replaced=$(find "$T/sdk" -maxdepth 1 -name 'go.replaced.*' -print)
assert_equals "1" "$(printf '%s\n' "$replaced" | grep -c .)" \
    "S8: exactly one go.replaced.* entry in sdk/"
assert_file_exists "$replaced/junk" "S8: replaced sdk keeps the old content"

# S9: rows with a wrong option are rejected, naming the row
bad_row=$(printf 'env/bin/x\ttarball\tfile://%s/fixtures/age.tgz\t%s\t-' \
    "$T" "$AGE_SHA")
printf '%s\n' "$bad_row" > "$T/manifest.tsv"
run_installer
assert_exit_code 1 $? "S9: tarball row with option '-' must exit 1"
assert_contains "$(cat "$T/run.out")" "$bad_row" \
    "S9: error output names the bad row"
bad_row=$(printf 'env/bin/y\tfile\tfile://%s/fixtures/neofetch\t%s\textract=x' \
    "$T" "$NEO_SHA")
printf '%s\n' "$bad_row" > "$T/manifest.tsv"
run_installer
assert_exit_code 1 $? "S9: file row with option 'extract=x' must exit 1"
assert_contains "$(cat "$T/run.out")" "$bad_row" \
    "S9: error output names the bad row"

# S10: env_vars exposes the sdk go path when the system has no go
env_vars_file="$ENV_DIR/env_vars"
assert_file_exists "$env_vars_file" "S10: env_vars exists"
assert_contains "$(cat "$env_vars_file")" "go-1.27.0/bin/go" \
    "S10: env_vars references the sdk go path"
assert_contains "$(cat "$env_vars_file")" "command -v go" \
    "S10: env_vars checks for a system go first"

print_test_summary
