#!/usr/bin/env bash
# resync-until-done.sh — keeps running bisync --resync until the pair's listings
# commit (= init succeeded), surviving reboots and transient failures.
# On success: pings Telegram and disables its own unit (the regular 2h timer
# takes over). flock in bisync-run.sh makes it safe alongside other runs.
set -u
LST="$HOME/.cache/rclone/bisync/media_yashar_Backups..hetzner-sftp_.path1.lst"
LAST_FAIL_PING=/home/yashar/logs/.resync-fail-ping
set -a; source /home/yashar/.config/ailaw-pr-review/env; set +a
SEND=/home/yashar/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh

while [ ! -f "$LST" ]; do
    /home/yashar/storagebox-sync/bisync-run.sh --resync --max-transfer 2T
    [ -f "$LST" ] && break
    now=$(date +%s)
    last=$(stat -c %Y "$LAST_FAIL_PING" 2>/dev/null || echo 0)
    if [ $((now - last)) -ge 3600 ]; then
        touch "$LAST_FAIL_PING"
        "$SEND" --loud "⚠️ StorageBox bisync resync attempt failed — auto-retrying every 5 min (unit storagebox-resync.service). Log: ~/logs/storagebox-bisync.log"
    fi
    sleep 300
done

"$SEND" "✅ StorageBox bisync resync COMPLETE — listings committed. Regular 2h timer now owns syncing; storagebox-resync.service disabled itself."
rm -f "$LAST_FAIL_PING"
systemctl --user disable storagebox-resync.service
