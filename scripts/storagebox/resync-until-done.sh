#!/usr/bin/env bash
# resync-until-done.sh — keeps running a full bisync --resync pass
# (scripts/storagebox/bisync-run.sh) until it succeeds, surviving reboots
# and transient failures. While it fails, pings Telegram at most hourly.
# On the first success: pings Telegram, removes the ping file and disables
# its own unit (the regular 2h timer takes over). flock in bisync-run.sh
# makes it safe alongside other runs.
set -u

RESYNC_RUNNER="${RESYNC_RUNNER:-/home/yashar/storagebox-sync/bisync-run.sh}"
RESYNC_SEND="${RESYNC_SEND:-/home/yashar/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh}"
RESYNC_PING_FILE="${RESYNC_PING_FILE:-/home/yashar/logs/.resync-fail-ping}"
RESYNC_SLEEP="${RESYNC_SLEEP:-300}"
RESYNC_MAX_TRIES="${RESYNC_MAX_TRIES:-0}"
RESYNC_SYSTEMCTL="${RESYNC_SYSTEMCTL:-systemctl --user}"
RESYNC_ENV="/home/yashar/.config/ailaw-pr-review/env"

# $1 = "loud" or "plain", $2 = the message
send() {
    if [ -f "$RESYNC_ENV" ]; then
        set -a; source "$RESYNC_ENV"; set +a
    fi
    if [ "$1" = "loud" ]; then
        "$RESYNC_SEND" --loud "$2"
    else
        "$RESYNC_SEND" "$2"
    fi
}

# on a failed try: refresh the ping file (at most hourly) and ping Telegram
ping_fail() {
    local now last
    now=$(date +%s)
    last=$(stat -c %Y "$RESYNC_PING_FILE" 2>/dev/null || echo 0)
    if [ $((now - last)) -ge 3600 ]; then
        touch "$RESYNC_PING_FILE"
        local minutes=$((RESYNC_SLEEP / 60))
        local msg
        msg="⚠️ StorageBox bisync resync attempt $1 failed —"
        msg="$msg auto-retrying every $minutes min"
        msg="$msg (unit storagebox-resync.service)."
        msg="$msg Log: ~/logs/storagebox-bisync.log"
        send loud "$msg"
    fi
}

main() {
    local tries=0 rc
    while true; do
        BISYNC_LOCKED_EXIT=75 "$RESYNC_RUNNER" --resync --max-transfer 2T
        rc=$?
        if [ "$rc" -eq 0 ]; then
            break
        fi
        if [ "$rc" -eq 75 ]; then
            # another run holds the lock: wait quietly, not a failed try
            sleep "$RESYNC_SLEEP"
            continue
        fi
        tries=$((tries + 1))
        ping_fail "$tries"
        if [ "$RESYNC_MAX_TRIES" -gt 0 ] && [ "$tries" -ge "$RESYNC_MAX_TRIES" ]; then
            echo "giving up after $tries tries" >&2
            exit 1
        fi
        sleep "$RESYNC_SLEEP"
    done

    local msg
    msg="✅ StorageBox bisync resync COMPLETE — every pair re-baselined."
    msg="$msg Regular sync now owns it; storagebox-resync.service"
    msg="$msg disabled itself."
    send plain "$msg"
    rm -f "$RESYNC_PING_FILE"
    $RESYNC_SYSTEMCTL disable storagebox-resync.service
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
