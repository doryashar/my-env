#!/usr/bin/env bash
# Behavioural tests for scripts/storagebox/merkle-snap.sh
# (temp tree, stub sender; nothing is written under ~/logs).
#
# Covers:
#   - baseline picture created for a fresh tree
#   - added and removed files counted in the net sums
#   - emptying a directory trips the wire (exit 3, one alert, stable after)
#   - byte loss inside an existing directory trips the wire
#   - losing more than 1000 files trips the wire
#   - a whole directory removed trips the wire
#   - MERKLE_NO_TG=1 suppresses the alert
#   - stable runs send nothing; diff-latest.txt stays in the snap dir
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${MERKLE_SCRIPT:-$SCRIPT_DIR/../scripts/storagebox/merkle-snap.sh}"

# shellcheck source=test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

echo "========================================"
echo "Merkle Snapshot Tests"
echo "========================================"
echo ""

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/tree"
cat > "$T/send.sh" <<EOF
#!/bin/bash
echo "\$*" >> "$T/sent.txt"
EOF
chmod +x "$T/send.sh"

run() {
    MERKLE_SNAP_DIR="$T/snaps" MERKLE_SEND="$T/send.sh" \
        bash "$SCRIPT" "$T/tree" > "$T/run.out" 2>&1
}

mkfiles() {
    local dir="$1" name="$2" count="$3"
    local i
    mkdir -p "$dir"
    for ((i = 1; i <= count; i++)); do
        echo x > "$dir/$name$i"
    done
}

logline() { tail -1 "$T/snaps/merkle.log" 2>/dev/null; }

sent() {
    if [[ -f "$T/sent.txt" ]]; then
        wc -l < "$T/sent.txt"
    else
        echo 0
    fi
}

snaps() { ls "$T/snaps"/snap-*.tsv 2>/dev/null | wc -l; }

walktemps() { ls "$T/snaps"/.walk.* 2>/dev/null | wc -l; }

# S1: baseline picture
mkfiles "$T/tree/a" f 50
mkfiles "$T/tree/b" g 50
run
assert_exit_code 0 $? "S1: baseline run must exit 0"
assert_equals "1" "$(snaps)" "S1: one snapshot created"
assert_contains "$(logline)" "baseline picture created: 2 dirs" \
    "S1: log records the baseline picture"
assert_equals "0" "$(sent)" "S1: nothing sent"

# S2: added files counted as net gain
echo new > "$T/tree/a/f51"
run
assert_exit_code 0 $? "S2: adding a file must exit 0"
assert_contains "$(logline)" "net files 1," "S2: net files gained 1"

# S3: deleted files counted as net loss
rm "$T/tree/a/f1" "$T/tree/a/f2" "$T/tree/a/f3" \
   "$T/tree/a/f4" "$T/tree/a/f5"
run
assert_exit_code 0 $? "S3: deleting five files must exit 0"
assert_contains "$(logline)" "net files -5," "S3: net files lost 5"

# S4: emptying a directory trips the wire once
rm -f "$T/tree/b/g"*
run
assert_exit_code 3 $? "S4: emptying a directory must exit 3"
assert_equals "1" "$(sent)" "S4: one alert sent"
assert_contains "$(tail -1 "$T/sent.txt")" "Merkle tripwire" \
    "S4: alert says Merkle tripwire"
assert_equals "0" "$(walktemps)" "S4: no walk temp file left"
run
assert_exit_code 0 $? "S4: unchanged tree must exit 0"
assert_equals "1" "$(sent)" "S4: no further alert on a stable tree"

# S5: byte loss inside an existing directory trips the wire
mkdir -p "$T/tree/c"
truncate -s 11G "$T/tree/c/big"
run
assert_exit_code 0 $? "S5: adding a large file must exit 0"
truncate -s 1G "$T/tree/c/big"
run
assert_exit_code 3 $? "S5: losing 10 GB must exit 3"
assert_equals "2" "$(sent)" "S5: one more alert sent"

# S6: losing more than 1000 files trips the wire
mkfiles "$T/tree/d" h 1600
run
assert_exit_code 0 $? "S6: adding 1600 files must exit 0"
rm -f "$T/tree/d/h"{101..1600}
run
assert_exit_code 3 $? "S6: losing 1500 files must exit 3"
assert_equals "3" "$(sent)" "S6: one more alert sent"

# S7: a whole directory removed trips the wire
rm -rf "$T/tree/d"
run
assert_exit_code 3 $? "S7: removing a directory must exit 3"
assert_equals "4" "$(sent)" "S7: one more alert sent"

# S8: MERKLE_NO_TG=1 suppresses the alert
export MERKLE_NO_TG=1
rm -f "$T/tree/a/f"*
run
assert_exit_code 3 $? "S8: emptying a directory must exit 3"
assert_equals "4" "$(sent)" "S8: no alert when MERKLE_NO_TG=1"
unset MERKLE_NO_TG

# S9: stable runs send nothing
run
assert_exit_code 0 $? "S9a: first stable run must exit 0"
run
assert_exit_code 0 $? "S9b: second stable run must exit 0"
assert_equals "4" "$(sent)" "S9: stable runs send nothing"

# S10: diff-latest.txt exists in the snap dir
assert_file_exists "$T/snaps/diff-latest.txt" \
    "S10: diff-latest.txt exists in the snap dir"

print_test_summary
