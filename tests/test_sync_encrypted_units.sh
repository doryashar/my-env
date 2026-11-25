#!/bin/bash

#########################################################################
# Unit tests for sync_encrypted.sh internals:
#   - hashit/has_changed: content-only, relative-path change detection
#   - DEBRIS_PREDICATE: editor debris never hashed or encrypted
#   - encrypt/decrypt round-trip via age (skipped if age missing)
#
# Loads the script's function definitions only (trap + main stripped),
# with all state redirected to a temp fixture. No network, no vault.
#########################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

SRC="$SCRIPT_DIR/../scripts/sync/sync_encrypted.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Neutralize side effects of sourcing the real script
mkdir -p "$TEST_DIR/bin"
printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/bin/ssh-keyscan"
chmod +x "$TEST_DIR/bin/ssh-keyscan"
export PATH="$TEST_DIR/bin:$PATH"


assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should not contain substring}"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "${GREEN}✓${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $message"
        echo "  Found: $needle"
        echo "  In: $haystack"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}
# Load definitions (everything except the EXIT trap and main). ENV_DIR is
# derived from BASH_SOURCE, which inside eval is THIS file and resolves one
# level too high — patch it to the real repo root so common_funcs loads.
REAL_ENV="$(cd "$SCRIPT_DIR/.." && pwd)"
eval "$(sed -e "s|^ENV_DIR=.*|ENV_DIR=\"$REAL_ENV\"|" \
            -e '/^trap cleanup EXIT$/d' \
            -e '/^# Run only when executed/,$d' "$SRC")"
# The script runs under set -euo pipefail; relax for the test driver
set +e; set +u; set +o pipefail

# Redirect all state into the fixture
DECRYPTED_DIR="$TEST_DIR/private"
LOCAL_REPO_PATH="$TEST_DIR/private_encrypted"
LOCAL_HASH_FILE="$TEST_DIR/local_hashes"
TEMP_DIR="$TEST_DIR/temp"
RECIPIENTS_FILE="$TEST_DIR/age-recipients"
mkdir -p "$DECRYPTED_DIR" "$LOCAL_REPO_PATH" "$TEMP_DIR"

# Generate a throwaway age keypair up front (encryption tests need a
# recipient file even before the round-trip check)
if command -v age-keygen &>/dev/null; then
    KEY_FILE="$TEST_DIR/age-key"
    age-keygen -o "$KEY_FILE" 2>/dev/null
    chmod 600 "$KEY_FILE"
    AGE_SECRET=$(cat "$KEY_FILE")
    age-keygen -y "$KEY_FILE" > "$RECIPIENTS_FILE" 2>/dev/null
fi

# --- Test 1: hashit uses relative paths -------------------------------
echo "alpha" > "$DECRYPTED_DIR/file1"
hashit "$DECRYPTED_DIR" "$LOCAL_HASH_FILE"
assert_not_contains "$(cat "$LOCAL_HASH_FILE")" "/home/" \
  "hash file contains no absolute home paths"
assert_not_contains "$(cat "$LOCAL_HASH_FILE")" "$TEST_DIR" \
  "hash file contains no fixture-absolute paths"

# --- Test 2: touch/chmod are not changes; content edits are ----------
sleep 1  # ensure mtime would differ if it were hashed
touch "$DECRYPTED_DIR/file1"
chmod 640 "$DECRYPTED_DIR/file1"
has_changed "$DECRYPTED_DIR" "$LOCAL_HASH_FILE"
assert_exit_code 0 $? "touch+chmod alone does not count as a change"

echo "beta" > "$DECRYPTED_DIR/file2"
has_changed "$DECRYPTED_DIR" "$LOCAL_HASH_FILE"
assert_exit_code 1 $? "new content counts as a change"

# --- Test 3: editor debris never hashed or encrypted ------------------
echo "junk" > "$DECRYPTED_DIR/editor.bak-20261117"
echo "junk" > "$DECRYPTED_DIR/#config#"
echo "junk" > "$DECRYPTED_DIR/backup~"
hashit "$DECRYPTED_DIR" "$LOCAL_HASH_FILE"
assert_not_contains "$(cat "$LOCAL_HASH_FILE")" ".bak-" \
  "hash file excludes .bak-* debris"
assert_not_contains "$(cat "$LOCAL_HASH_FILE")" "#config#" \
  "hash file excludes emacs lock files"
assert_not_contains "$(cat "$LOCAL_HASH_FILE")" "backup~" \
  "hash file excludes tilde backups"

encrypt_recursive "$DECRYPTED_DIR" "$LOCAL_REPO_PATH"
assert_file_not_exists "$LOCAL_REPO_PATH/editor.bak-20261117.age" \
  "encryption skips .bak-* debris"
assert_file_not_exists "$LOCAL_REPO_PATH/#config#.age" \
  "encryption skips emacs lock files"
assert_file_not_exists "$LOCAL_REPO_PATH/backup~.age" \
  "encryption skips tilde backups"
assert_file_exists "$LOCAL_REPO_PATH/file1.age" \
  "real files still encrypted"

# --- Test 4: encrypt/decrypt round-trip (needs age) -------------------
if command -v age-keygen &>/dev/null; then
    KEY_FILE="$TEST_DIR/age-key"
    age-keygen -o "$KEY_FILE" 2>/dev/null
    chmod 600 "$KEY_FILE"
    AGE_SECRET=$(cat "$KEY_FILE")
    age-keygen -y "$KEY_FILE" > "$RECIPIENTS_FILE" 2>/dev/null

    ROUNDTRIP="$TEST_DIR/roundtrip"
    mkdir -p "$ROUNDTRIP"
    echo "secret-content-$RANDOM" > "$DECRYPTED_DIR/roundtrip.txt"
    encrypt_file "$DECRYPTED_DIR/roundtrip.txt" "$ROUNDTRIP/roundtrip.txt.age"
    decrypt_file "$ROUNDTRIP/roundtrip.txt.age" "$ROUNDTRIP/roundtrip.txt"
    assert_contains "$(cat "$ROUNDTRIP/roundtrip.txt" 2>/dev/null)" "secret-content-" \
      "age encrypt/decrypt round-trip preserves content"
else
    echo -e "${YELLOW}SKIP${NC} age-keygen not found - round-trip test skipped"
fi

print_test_summary
