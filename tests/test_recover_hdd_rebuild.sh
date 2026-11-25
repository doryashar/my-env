#!/usr/bin/env bash
# Behavioural tests for scripts/storagebox/recover-hdd-rebuild.sh (task 17).
#
# Every external command the script can reach is a stub in $T/bin (first in
# PATH); the destructive commands are never actually run. The disk under
# test is a real loop device, used only for the [[ -b ]] check.
#
# Covers R1-R9: argument handling, the pre-flight refusals (not a block
# device, partition instead of whole disk, system disk, mounted), the
# dry-run plan, the no-terminal confirmation refusal, and the non-root
# refusal.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export T

SCRIPT="$SCRIPT_DIR/../scripts/storagebox/recover-hdd-rebuild.sh"
mkdir -p "$T/bin"
: > "$T/calls"

# The disk under test: the first real loop block device; the suite stops
# without it (nothing here may be touched).
DISK=""
for cand in /dev/loop0 /dev/loop1 /dev/loop-control; do
    if [[ -b "$cand" ]]; then DISK="$cand"; break; fi
done
if [[ -z "$DISK" ]]; then
    echo "SKIP: no loop block device available; recover-hdd-rebuild tests not run"
    if print_test_summary; then exit 0; fi
    exit 1
fi
export DISK
mkdir -p "$T/sysblock/${DISK##*/}/holders"
export REBUILD_SYS_BLOCK="$T/sysblock"
echo "test disk: $DISK (never touched; all commands are stubs)"
echo ""

# --- stubs --------------------------------------------------------------------
for cmd in wipefs sgdisk partprobe mkfs.ntfs mount chown cp rclone sudo systemctl runuser; do
    printf '#!/bin/bash\necho "%s $*" >> "$T/calls"\nexit 0\n' "$cmd" > "$T/bin/$cmd"
    chmod +x "$T/bin/$cmd"
done

# sed: record the call; a mutating edit (-i) is stubbed away, a read-only
# invocation (the usage text) passes through to the real sed.
cat > "$T/bin/sed" <<'STUB'
#!/bin/bash
echo "sed $*" >> "$T/calls"
for a in "$@"; do
    [ "$a" = "-i" ] && exit 0
done
exec /usr/bin/sed "$@"
STUB
chmod +x "$T/bin/sed"

printf '#!/bin/bash\necho "blkid $*" >> "$T/calls"\necho "NEWUUID-1"\nexit 0\n' > "$T/bin/blkid"
chmod +x "$T/bin/blkid"

printf '#!/bin/bash\necho "df $*" >> "$T/calls"\necho "Filesystem  Size  Used Avail Use%% Mounted on"\necho "/dev/sdb1   2.0T  100G  1.9T   6%% /media/yashar/Backups"\nexit 0\n' > "$T/bin/df"
chmod +x "$T/bin/df"

cat > "$T/bin/lsblk" <<'STUB'
#!/bin/bash
echo "lsblk $*" >> "$T/calls"
o=""
s=0
args=("$@")
i=0
n=${#args[@]}
while [ "$i" -lt "$n" ]; do
    a="${args[i]}"
    case "$a" in
        -o) o="${args[i+1]}"; i=$((i+1)) ;;
        -o?*) o="${a#-o}" ;;
        -*)
            case "${a#-}" in
                *s*) s=1 ;;
            esac
            case "${a#-}" in
                *o*) o="${args[i+1]}"; i=$((i+1)) ;;
            esac
            ;;
    esac
    i=$((i+1))
done
if [ "$s" = "1" ]; then
    last="${args[${#args[@]}-1]}"
    if [ -n "${STUB_CHAIN:-}" ] \
       && { [ -z "${STUB_CHAIN_SRC:-}" ] || [ "$last" = "/dev/${STUB_CHAIN_SRC}" ]; }; then
        echo "${STUB_CHAIN}"
    fi
fi
if [ "$o" = "TYPE" ]; then
    echo "${STUB_DISK_TYPE:-disk}"
elif [ "$o" = "PKNAME" ]; then
    last="${@: -1}"
    if [ -n "${STUB_ROOT_PART:-}" ] && [ "$last" = "/dev/${STUB_ROOT_PART}" ]; then
        echo "${STUB_ROOT_PARENT:-}"
    else
        echo "${STUB_DISK_PKNAME:-}"
    fi
elif [ "$o" = "NAME,MODEL,SERIAL,SIZE" ]; then
    echo "${DISK##*/}  StubModel  StubSerial  2.0T"
elif [ "$o" = "NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT" ] || [ "$o" = "NAME,MOUNTPOINT" ]; then
    [ -n "${STUB_DISK_MOUNTS:-}" ] && printf '%s\n' "$STUB_DISK_MOUNTS"
fi
exit 0
STUB
chmod +x "$T/bin/lsblk"

cat > "$T/bin/findmnt" <<'STUB'
#!/bin/bash
echo "findmnt $*" >> "$T/calls"
for a in "$@"; do
    [ "$a" = "-S" ] && exit 1
done
echo "/dev/${STUB_ROOT_PART:-nvme0n1p2}"
exit 0
STUB
chmod +x "$T/bin/findmnt"

# --- helpers -------------------------------------------------------------------
RUN_OUT=""
RUN_RC=0
run() {
    RUN_OUT="$(PATH="$T/bin:$PATH" bash "$SCRIPT" "$@" </dev/null 2>&1)"
    RUN_RC=$?
}
run_setsid() {
    RUN_OUT="$(setsid -w env PATH="$T/bin:$PATH" bash "$SCRIPT" "$@" </dev/null 2>&1)"
    RUN_RC=$?
}
called() {
    grep -q "^$1 " "$T/calls" 2>/dev/null
}

# --- R1: no argument -----------------------------------------------------------
: > "$T/calls"
run
assert_exit_code 2 "$RUN_RC" "R1: no argument exits 2"

# --- R2: --help -----------------------------------------------------------------
: > "$T/calls"
run --help
assert_exit_code 0 "$RUN_RC" "R2: --help exits 0"
assert_contains "$RUN_OUT" "Usage" "R2: --help prints the usage"

# --- R3: not a block device -------------------------------------------------------
: > "$T/calls"
run "$T/not-a-device"
assert_exit_code 1 "$RUN_RC" "R3: not a block device exits 1"
assert_contains "$RUN_OUT" "not a block device" "R3: refusal message"

# --- R4: a partition, not a whole disk ---------------------------------------------
: > "$T/calls"
export STUB_DISK_TYPE=part
run "$DISK"
unset STUB_DISK_TYPE
assert_exit_code 1 "$RUN_RC" "R4: partition refused, exit 1"
assert_contains "$RUN_OUT" "whole disk" "R4: whole-disk refusal message"
assert_equals "" "$(grep '^wipefs ' "$T/calls" 2>/dev/null)" "R4: wipefs not called"

# --- R5: the system disk ------------------------------------------------------------
: > "$T/calls"
export STUB_CHAIN="${DISK##*/}"
run "$DISK"
unset STUB_CHAIN
assert_exit_code 1 "$RUN_RC" "R5: system disk refused, exit 1"
assert_contains "$RUN_OUT" "system disk" "R5: system-disk refusal message"
assert_equals "" "$(grep '^wipefs ' "$T/calls" 2>/dev/null)" "R5: wipefs not called"

# --- R6: something mounted from it ---------------------------------------------------
: > "$T/calls"
export STUB_DISK_MOUNTS="${DISK##*/}p1 /mnt/x"
run "$DISK"
unset STUB_DISK_MOUNTS
assert_exit_code 1 "$RUN_RC" "R6: mounted disk refused, exit 1"
assert_contains "$RUN_OUT" "unmount" "R6: unmount refusal message"
assert_equals "" "$(grep '^wipefs ' "$T/calls" 2>/dev/null)" "R6: wipefs not called"

# --- R6b: holders (LVM, RAID or an open crypt device) -----------------------------
: > "$T/calls"
touch "$T/sysblock/${DISK##*/}/holders/dm-0"
run "$DISK"
assert_exit_code 1 "$RUN_RC" "R6b: disk with holders refused, exit 1"
assert_contains "$RUN_OUT" "in use by dm-0" "R6b: holders refusal message"
assert_equals "" "$(grep '^wipefs ' "$T/calls" 2>/dev/null)" "R6b: wipefs not called"
rm -f "$T/sysblock/${DISK##*/}/holders/dm-0"

# --- R6c: swap on the candidate -----------------------------------------------------
: > "$T/calls"
printf 'Filename\tType\tSize\tUsed\tPriority\n%s\tswap\t1024\t0\t-1\n' "${DISK}p3" > "$T/swaps"
export REBUILD_SWAPS_FILE="$T/swaps"
export STUB_CHAIN="${DISK##*/}"
export STUB_CHAIN_SRC="${DISK##*/}p3"
run "$DISK"
unset REBUILD_SWAPS_FILE STUB_CHAIN STUB_CHAIN_SRC
assert_exit_code 1 "$RUN_RC" "R6c: swap on the candidate refused, exit 1"
assert_contains "$RUN_OUT" "system disk" "R6c: system-disk refusal message"
assert_equals "" "$(grep '^wipefs ' "$T/calls" 2>/dev/null)" "R6c: wipefs not called"

# --- R7: --dry-run ---------------------------------------------------------------------
: > "$T/calls"
run --dry-run "$DISK"
assert_exit_code 0 "$RUN_RC" "R7: --dry-run exits 0"
assert_contains "$RUN_OUT" "ERASES" "R7: plan warns that the disk is erased"
assert_contains "$RUN_OUT" "dry run: nothing was changed" "R7: dry-run confirmation line"
assert_equals "" "$(grep '^wipefs ' "$T/calls" 2>/dev/null)" "R7: wipefs not called"

# --- R8: no --yes and no terminal ---------------------------------------------------------
: > "$T/calls"
run_setsid "$DISK"
assert_exit_code 1 "$RUN_RC" "R8: no confirmation possible, exit 1"
assert_contains "$RUN_OUT" "confirmation did not match" "R8: confirmation refusal message"
assert_equals "" "$(grep '^wipefs ' "$T/calls" 2>/dev/null)" "R8: wipefs not called"

# --- R9: --yes without root ------------------------------------------------------------------
: > "$T/calls"
run --yes "$DISK"
assert_exit_code 1 "$RUN_RC" "R9: non-root run exits 1"
assert_contains "$RUN_OUT" "must run as root" "R9: root refusal message"
assert_equals "yes" "$(called lsblk && echo yes || echo no)" "R9: lsblk called (read-only pre-flight ran)"
assert_equals "yes" "$(called findmnt && echo yes || echo no)" "R9: findmnt called (read-only pre-flight ran)"
for c in wipefs sgdisk partprobe mkfs.ntfs blkid mount chown sed cp rclone sudo systemctl runuser df; do
    assert_equals "" "$(grep "^$c " "$T/calls" 2>/dev/null)" "R9: $c not called"
done
# --- results -----------------------------------------------------------------------------
if print_test_summary; then
    exit 0
fi
exit 1
