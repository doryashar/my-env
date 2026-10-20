#!/bin/bash
export TELEGRAM_BOT_TOKEN="7943280211:$(grep -oP '(?<=^TELEGRAM_BOT_TOKEN=bot7943280211:).+' ~/.config/ailaw-pr-review/env)"
export TELEGRAM_CHAT_ID="6709569660"
SEND=~/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh
LOG=/home/yashar/logs/push-workers.log
total_items=$(ls -A /media/yashar/Backups | wc -l)
done_items=$(grep -c "done: " "$LOG" 2>/dev/null); done_items=${done_items:-0}
running=$(pgrep -c -x rsync 2>/dev/null); running=${running:-0}
current=$(grep "start: " "$LOG" | tail -4 | sed 's/.*start: //' | tr '\n' ',' | sed 's/,$//')
box_free=$(df -h /mnt/StorageBox 2>/dev/null | awk 'END{print $4}')
drive_free=$(df -h /media/yashar/Backups 2>/dev/null | awk 'END{print $4}')
pushed_gb=$(du -sh /media/yashar/Backups 2>/dev/null | cut -f1)
svc_watch=$(systemctl --user is-active storagebox-watcher.service 2>/dev/null)
svc_timer=$(systemctl --user is-active storagebox-bisync.timer 2>/dev/null)
all_done=$(grep -c "ALL PUSH DONE" "$LOG" 2>/dev/null); all_done=${all_done:-0}
if [ "$all_done" -gt 0 ]; then
  state="initial push COMPLETE"
else
  state="push in progress: $done_items/$total_items top-level items done, $running rsync workers running"
fi
MSG="⏳ Backups -> StorageBox sync status ($(date '+%H:%M')):

• $state
• currently: ${current:-n/a}
• drive: ${drive_free} free | box: ${box_free} free
• services: watcher=$svc_watch timer=$svc_timer (activated after initial push completes)
• note: box SFTP stack changed post-upgrade (mod_sftp) - bisync transport switch to WebDAV pending after bulk push"
bash "$SEND" "$MSG"
