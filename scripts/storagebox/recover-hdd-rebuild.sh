#!/usr/bin/env bash
# recover-hdd-rebuild.sh — definitive rebuild of the Backups HDD:
# GPT + partition + fresh NTFS (fixes partitionless + corruption), then
# full restore from the Storage Box, then fresh bisync init.
# Run as ROOT (needs sudo for disk ops; rclone uses yashar's config
# explicitly).
#
# Usage:
#   sudo recover-hdd-rebuild.sh [--dry-run] [--yes] DISK
#   DISK        whole disk to erase and rebuild (required; no default)
#   --dry-run   pre-flight checks and printed plan, then stop; nothing changes
#   --yes       skip the interactive confirmation
#   --help      show this usage and exit 0
#   (confirmation, when asked, is the literal text: ERASE <DISK>)
set -u
MNT=/media/yashar/Backups
LOG=/home/yashar/logs/storagebox-rebuild.log
RCF=/home/yashar/.config/rclone/rclone.conf
RCLONE=/usr/local/bin/rclone
FSTAB="${REBUILD_FSTAB:-/etc/fstab}"
REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
SYS_BLOCK="${REBUILD_SYS_BLOCK:-/sys/block}"
SWAPS_FILE="${REBUILD_SWAPS_FILE:-/proc/swaps}"

error() { echo "recover-hdd-rebuild: ERROR: $*" >&2; }

usage() { sed -n '/^# Usage:$/,/^#   (confirmation/p' "$0" | sed 's/^# \{0,1\}//'; }

DRY_RUN=0
AUTO_YES=0
DISK=
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --yes) AUTO_YES=1 ;;
        --help) usage; exit 0 ;;
        -*)
            error "unknown option: $1"
            exit 2
            ;;
        *)
            if [ -z "$DISK" ]; then
                DISK="$1"
            else
                error "unexpected argument: $1"
                exit 2
            fi
            ;;
    esac
    shift
done
if [ -z "$DISK" ]; then
    usage >&2
    exit 2
fi

# --- pre-flight (no privileges needed) ---------------------------------------
# a. must be a block device
[[ -b "$DISK" ]] || { error "not a block device"; exit 1; }

# b. whole disk only
if [[ "$(lsblk -dn -o TYPE "$DISK" 2>/dev/null)" != "disk" ]] \
   || [[ "$DISK" == /dev/zram* ]]; then
    error "pass a whole disk, not a partition or a virtual device"
    exit 1
fi

# d. nothing mounted from it
if [ -n "$(findmnt -S "$DISK" -no TARGET 2>/dev/null)" ] \
   || [ -n "$(lsblk -nro NAME,MOUNTPOINT "$DISK" 2>/dev/null | awk 'NF >= 2' | head -1)" ]; then
    error "unmount its partitions first"
    exit 1
fi

# f. no holders (LVM, RAID, or an open crypt device)
holders_dir="$SYS_BLOCK/$(basename "$DISK")/holders"
holders=""
for h in "$holders_dir"/*; do
    [ -e "$h" ] || continue
    holders="${holders:+$holders }$(basename "$h")"
done
if [ -n "$holders" ]; then
    error "disk is in use by $holders (LVM, RAID or an open crypt device)"
    exit 1
fi

# g. never the system disk (LVM or encrypted roots included)
for mp in / /boot /boot/efi; do
    src=$(findmnt -no SOURCE -T "$mp" 2>/dev/null)
    [ -n "$src" ] || continue
    if lsblk -s -n -o NAME "$src" 2>/dev/null | grep -qx "$(basename "$DISK")"; then
        error "refusing to erase the system disk"
        exit 1
    fi
done
swap_devs=$(tail -n +2 "$SWAPS_FILE" 2>/dev/null | awk 'NF { print $1 }')
for src in $swap_devs; do
    [ -n "$src" ] || continue
    if lsblk -s -n -o NAME "$src" 2>/dev/null | grep -qx "$(basename "$DISK")"; then
        error "refusing to erase the system disk"
        exit 1
    fi
done

# h. the plan
lsblk -d -o NAME,MODEL,SERIAL,SIZE "$DISK"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$DISK"
echo "This ERASES everything on $DISK"
echo "new layout: GPT with one NTFS partition labelled Backups, mounted at $MNT"
echo "fstab: $FSTAB"
echo "then: full restore from the Storage Box and a bisync re-baseline"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "dry run: nothing was changed"
    exit 0
fi

# --- confirmation ------------------------------------------------------------
if [ "$AUTO_YES" -ne 1 ]; then
    echo "To proceed, type: ERASE $DISK"
    read -r reply </dev/tty || reply=""
    if [ "$reply" != "ERASE $DISK" ]; then
        error "confirmation did not match; nothing was changed"
        exit 1
    fi
fi

# --- root ---------------------------------------------------------------------
[ "$EUID" -eq 0 ] || { error "must run as root (sudo …)"; exit 1; }

set -a; source /home/yashar/.config/ailaw-pr-review/env; set +a
SEND=/home/yashar/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh
say() { "$SEND" "$1"; }
log() { echo "$(date -Is) $*" >> "$LOG"; }

log "=== rebuild start: wiping $DISK"

# OLD_UUID: the UUID of the $MNT line in $FSTAB (may be empty)
OLD_UUID=$(awk -v mnt="$MNT" '$1 ~ /^UUID=/ && $2 == mnt { s = $1; sub(/^UUID=/, "", s); print s; exit }' "$FSTAB" 2>/dev/null)

NEWP="${DISK}1"

wipefs -a "$DISK" >> "$LOG" 2>&1 || { say "❌ HDD rebuild failed at wipefs — see $LOG"; exit 1; }
sgdisk -o -n 1:0:0 -t 1:0700 -c 1:"Backups" "$DISK" >> "$LOG" 2>&1 || { say "❌ HDD rebuild failed at partitioning — see $LOG"; exit 1; }
partprobe "$DISK" >> "$LOG" 2>&1 || { say "❌ HDD rebuild failed at partprobe — see $LOG"; exit 1; }
sleep 3

log "formatting $NEWP"
mkfs.ntfs --quick -L Backups "$NEWP" >> "$LOG" 2>&1 || { say "❌ HDD rebuild failed at mkfs — see $LOG"; exit 1; }

NEW_UUID=$(blkid -s UUID -o value "$NEWP") || { say "❌ HDD rebuild failed to read the new UUID — see $LOG"; exit 1; }
[ -n "$NEW_UUID" ] || { say "❌ HDD rebuild failed to read the new UUID — see $LOG"; exit 1; }
log "new volume UUID: $NEW_UUID"

# fstab + mount-check + test UUID updates (only files that contain OLD_UUID)
if [ -n "$OLD_UUID" ]; then
    cp "$FSTAB" "$FSTAB.backup.$(date +%Y%m%d%H%M%S)"
    for f in "$FSTAB" "$REPO_DIR/scripts/storagebox/mount-check.sh" "$REPO_DIR/tests/test_mount_check.sh"; do
        if [ -f "$f" ] && grep -q "$OLD_UUID" "$f"; then
            sed -i "s/$OLD_UUID/$NEW_UUID/" "$f" || { say "❌ HDD rebuild failed updating $f — see $LOG"; exit 1; }
        fi
    done
else
    log "WARNING: no UUID line for $MNT in $FSTAB — enter $NEW_UUID by hand"
    echo "WARNING: no UUID line for $MNT in $FSTAB — enter $NEW_UUID by hand" >&2
fi

mount "$MNT" || { say "❌ HDD rebuild: mount failed — see $LOG"; exit 1; }
chown yashar:yashar "$MNT" || { say "❌ HDD rebuild: chown failed — see $LOG"; exit 1; }

# invalidate old bisync listings (pair is being re-initialized after restore)
rm -f /home/yashar/.cache/rclone/bisync/storagebox-pairs.txt
rm -f /home/yashar/.cache/rclone/bisync/media_yashar_Backups*

log "=== restore from Box begins (2.6T — many hours)"
"$RCLONE" copy "hetzner-sftp:/" "$MNT" --config "$RCF" \
    --transfers 8 --checkers 8 --multi-thread-streams 1 \
    --retries 5 --low-level-retries 20 \
    --log-file "$LOG" --log-level INFO
rc=$?
log "restore exit=$rc"
if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
    say "❌ HDD rebuild restore FAILED (rc=$rc) — see $LOG"
    exit 1
fi

# everything that must run as the user goes through one helper
as_user() { sudo -u yashar env HOME=/home/yashar XDG_RUNTIME_DIR=/run/user/$(id -u yashar) "$@"; }

log "=== fresh bisync init (resync; both sides identical)"
as_user /home/yashar/storagebox-sync/bisync-run.sh --resync
rc2=$?
log "resync exit=$rc2"

as_user /home/yashar/storagebox-sync/merkle-snap.sh >> "$LOG" 2>&1 \
    || { say "❌ HDD rebuild: merkle baseline failed — see $LOG"; exit 1; }

as_user systemctl --user start storagebox-bisync.timer storagebox-status-bihourly.timer storagebox-merkle.timer \
    || { say "❌ HDD rebuild: failed to start the storagebox timers — see $LOG"; exit 1; }

if [ "$rc2" -eq 0 ]; then
    say "✅ HDD rebuild COMPLETE — GPT partitioned, all data restored from Box, bisync re-initialized, timers resumed. (chkdsk no longer needed)"
else
    say "⚠️ HDD rebuilt + data restored, but bisync init exited $rc2 — check $LOG"
fi
