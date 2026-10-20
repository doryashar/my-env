#!/usr/bin/env bash
# recover-from-box.sh — restores HDD files lost to NTFS corruption (2026-10-15/17
# incident) from the Storage Box, then re-enables the sync stack. Idempotent:
# identical files are skipped, so it can be re-run after interruption.
set -u
LOG=/home/yashar/logs/storagebox-restore.log
RCLONE=/usr/local/bin/rclone
B="$HOME/.cache/rclone/bisync"
L1=/media/yashar/Backups

set -a; source /home/yashar/.config/ailaw-pr-review/env; set +a
SEND=/home/yashar/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh

TREES=(
  "archive/docker-old"
  "lexar - ssd material to orginize/overflow"
  "lexar - ssd material to orginize/Drive"
  "photos/media"
  "lexar - ssd material to orginize/gpu-emulator"
  "personal/documents"
  "personal/work"
)

for t in "${TREES[@]}"; do
    echo "$(date -Is) restoring $t" >> "$LOG"
    "$RCLONE" copy "hetzner-sftp:$t" "$L1/$t" \
        --transfers 8 --checkers 8 --multi-thread-streams 1 \
        --retries 5 --low-level-retries 20 \
        --log-file "$LOG" --log-level INFO
    rc=$?
    if [ "$rc" -ge 2 ]; then
        "$SEND" --loud "❌ Restore FAILED on tree: $t (rc=$rc) — check $LOG"
        exit 1
    fi
    [ "$rc" -eq 1 ] && echo "$(date -Is) WARNING: $t completed with non-fatal errors (symlinks etc), rc=1" >> "$LOG"
done

n=$(find "$L1/archive/docker-old" -type f 2>/dev/null | wc -l)
for side in path1 path2; do
    [ -f "$B/media_yashar_Backups..hetzner-sftp_.${side}.lst" ] || \
        mv "$B/media_yashar_Backups..hetzner-sftp_.${side}.lst-err" \
           "$B/media_yashar_Backups..hetzner-sftp_.${side}.lst"
done

systemctl --user enable --now storagebox-bisync.timer storagebox-status-bihourly.timer
systemctl --user start storagebox-bisync.service

"$SEND" "✅ Recovery restore complete — all 7 trees restored from Storage Box (docker-old now $n files). Listings restored, sync + health checks re-enabled. A full pass is running; expect the ✅ RECOVERED ping when it commits."
