#!/usr/bin/env bash
# whatsapp-media-relay.sh — continuously offload synced phone media from local
# disk to the StorageBox. rclone move deletes the LOCAL copy only after the
# box copy is verified (size+modtime). --min-age keeps in-flight syncthing
# downloads (.tmp, partial) safely out of reach.
set -u
SRC=/home/ubuntu/syncthing/whatsapp/new/media
DST=hetzner-storagebox:backup/whatsapp/new/media
LOG=/home/ubuntu/logs/whatsapp-media-relay.log
mkdir -p "$(dirname "$LOG")"
while true; do
  rclone move "$SRC" "$DST" \
    --min-age 3m \
    --exclude ".syncthing*" --exclude ".stfolder" \
    --transfers 4 --checkers 8 \
    --stats-one-line --stats 5m \
    --log-file "$LOG" --log-level INFO
  # exit non-zero → log it; the loop tolerates transient SMB errors
  rc=$?
  [ "$rc" -ne 0 ] && echo "$(date -Is) rclone move rc=$rc (retrying in 2m)" >> "$LOG"
  sleep 120
done
