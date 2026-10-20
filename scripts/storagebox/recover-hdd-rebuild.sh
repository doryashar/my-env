#!/usr/bin/env bash
# recover-hdd-rebuild.sh — definitive rebuild of the Backups HDD:
# GPT + partition + fresh NTFS (fixes partitionless + corruption), then full
# restore from the Storage Box, then fresh bisync init. Run as ROOT (needs
# sudo for disk ops; rclone uses yashar's config explicitly).
set -u
DISK=/dev/sda
MNT=/media/yashar/Backups
LOG=/home/yashar/logs/storagebox-rebuild.log
RCF=/home/yashar/.config/rclone/rclone.conf
RCLONE=/usr/local/bin/rclone

set -a; source /home/yashar/.config/ailaw-pr-review/env; set +a
SEND=/home/yashar/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh
say() { "$SEND" "$1"; }
log() { echo "$(date -Is) $*" >> "$LOG"; }

log "=== rebuild start: wiping $DISK"
wipefs -a "$DISK" >> "$LOG" 2>&1
sgdisk -o -n 1:0:0 -t 1:0700 -c 1:"Backups" "$DISK" >> "$LOG" 2>&1 || { say "❌ HDD rebuild failed at partitioning — see $LOG"; exit 1; }
partprobe "$DISK"; sleep 3

NEWP="${DISK}1"
log "formatting $NEWP"
mkfs.ntfs --quick -L Backups "$NEWP" >> "$LOG" 2>&1 || { say "❌ HDD rebuild failed at mkfs — see $LOG"; exit 1; }

NEWUUID=$(blkid -s UUID -o value "$NEWP")
log "new volume UUID: $NEWUUID"

# fstab + mount-check UUID updates
sed -i "s|^UUID=428E297D01064BA5 |UUID=$NEWUUID |" /etc/fstab
sed -i "s/428E297D01064BA5/$NEWUUID/" /home/yashar/env/scripts/storagebox/mount-check.sh
sed -i "s/428E297D01064BA5/$NEWUUID/" /home/yashar/tests/test_mount_check.sh 2>/dev/null
mount "$MNT" || { say "❌ HDD rebuild: mount failed — see $LOG"; exit 1; }
chown yashar:yashar "$MNT"

# invalidate old bisync listings (pair is being re-initialized after restore)
rm -f /home/yashar/.cache/rclone/bisync/media_yashar_Backups..hetzner-sftp_.*

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

log "=== fresh bisync init (resync; both sides identical)"
sudo -u yashar env HOME=/home/yashar /home/yashar/storagebox-sync/bisync-run.sh --resync
rc2=$?
log "resync exit=$rc2"

# merkle baseline + timers
sudo -u yashar env HOME=/home/yashar /home/yashar/storagebox-sync/merkle-snap.sh >> "$LOG" 2>&1
systemctl --user start storagebox-bisync.timer storagebox-status-bihourly.timer storagebox-merkle.timer 2>/dev/null \
    || runuser -u yashar -- systemctl --user start storagebox-bisync.timer storagebox-status-bihourly.timer storagebox-merkle.timer

if [ "$rc2" -eq 0 ]; then
    say "✅ HDD rebuild COMPLETE — GPT partitioned, all data restored from Box, bisync re-initialized, timers resumed. (chkdsk no longer needed)"
else
    say "⚠️ HDD rebuilt + data restored, but bisync init exited $rc2 — check $LOG"
fi
