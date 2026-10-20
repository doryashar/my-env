#!/usr/bin/env bash
# status-update.sh [auto2h|weekly] — Telegram status for the StorageBox sync.
# auto2h (every 2h): SILENT while healthy. Sends while unhealthy, plus a
#   one-time recovery notice. Covers alignment gaps (listings missing).
# weekly (Mon 09:00): always sends the weekly summary.
set -u
MODE="${1:-auto2h}"
LST="${STATUS_LST:-$HOME/.cache/rclone/bisync/media_yashar_Backups..hetzner-sftp_.path1.lst}"
LOG="${STATUS_LOG:-/home/yashar/logs/storagebox-bisync.log}"
UNHEALTHY_MARKER=/home/yashar/logs/.sync-unhealthy

set -a; source /home/yashar/.config/ailaw-pr-review/env; set +a
SEND=/home/yashar/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh

healthy() {
    [ -f "$LST" ] || return 1
    local errs
    errs=$(grep -c ERROR <(tail -200 "$LOG") 2>/dev/null); errs=${errs:-0}
    [ "$errs" -le 20 ] || return 1
    local last_exit
    last_exit=$(grep -oE 'bisync exit=[0-9]+' "$LOG" | tail -1 | grep -oE '[0-9]+$')
    [ "$last_exit" = "0" ] && return 0
    # stale non-zero exit is fine while a pass is live and the log is fresh
    local age
    age=$(( $(date +%s) - $(stat -c %Y "$LOG") ))
    pgrep -f 'rclone bisync' >/dev/null 2>&1 && [ "$age" -lt 1800 ]
}

snap() {
    local errs
    errs=$(grep -c ERROR <(tail -100 "$LOG") 2>/dev/null); errs=${errs:-0}
    local phase
    phase=$(grep -E 'INFO|NOTICE|ERROR' "$LOG" | tail -1 | cut -c12-100)
    local last
    last=$(grep -E 'bisync (start|exit)=' "$LOG" | tail -2 | tr '\n' ' ; ' | cut -c1-90)
    local drive_free box_free
    drive_free=$(df -h /media/yashar/Backups 2>/dev/null | awk 'END{print $4}')
    box_free=$(df -h /mnt/StorageBox 2>/dev/null | awk 'END{print $4}')
    local l1 l2 copied stats walk
    l1=$(wc -l < "$HOME/.cache/rclone/bisync/media_yashar_Backups..hetzner-sftp_.path1.lst" 2>/dev/null || echo 0)
    l2=$(wc -l < "$HOME/.cache/rclone/bisync/media_yashar_Backups..hetzner-sftp_.path2.lst" 2>/dev/null || echo 0)
    copied=$(awk '/bisync start/{n=0} /Copied/{n++} END{print n+0}' "$LOG" 2>/dev/null)
    stats=$(grep -E '^Transferred:' "$LOG" | tail -1 | sed 's/  */ /g')
    walk=$(grep -E '^Checks:' "$LOG" | tail -1 | sed 's/  */ /g')
    echo "• resync loop: $(systemctl --user is-active storagebox-resync.service 2>/dev/null)
• bisync timer: $(systemctl --user is-active storagebox-bisync.timer 2>/dev/null)
• pair listings: local $l1 / remote $l2 files
• copied this pass: $copied files
• progress: ${stats:-n/a}
• walk: ${walk:-n/a}
• last: $last
• errors (last 100 lines): $errs
• now: $phase
• drive: ${drive_free:-?} free | box: ${box_free:-?} free"
}

case "$MODE" in
auto2h)
    if healthy; then
        if [ -f "$UNHEALTHY_MARKER" ]; then
            rm -f "$UNHEALTHY_MARKER"
            "$SEND" "✅ StorageBox sync RECOVERED — back to healthy. Weekly status resumes.
$(snap)"
        fi
    else
        touch "$UNHEALTHY_MARKER"
        "$SEND" --loud "❌ StorageBox sync UNHEALTHY (bi-hourly updates until recovery):
$(snap)"
    fi
    ;;
weekly)
    local_ok=$(grep -c 'bisync exit=0' <(tail -2000 "$LOG"))
    local_fail=$(grep -c 'bisync exit=[1-9]' <(tail -2000 "$LOG"))
    week_copied=$(awk '/bisync start/{n=0} /Copied/{n++} END{print n+0}' <(tail -50000 "$LOG") 2>/dev/null)
    if healthy; then
        "$SEND" "📅 StorageBox sync weekly status:
• state: healthy (aligned)
• recent runs: $local_ok clean / $local_fail failed
• copied in recent passes: ${week_copied:-0} files
$(snap)"
    else
        "$SEND" --loud "📅 StorageBox sync weekly status: UNHEALTHY — bi-hourly updates active.
$(snap)"
    fi
    ;;
esac
