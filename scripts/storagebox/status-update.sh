#!/usr/bin/env bash
# status-update.sh [auto2h|weekly] — Telegram status for the StorageBox sync.
# Health is decided from the runner's pass summary: `pass start` at the
# start of a pass, `pass exit=N failed=a,b` at the end, plus per-pair
# `pair[NAME] exit=N` lines (scripts/storagebox/bisync-run.sh).
# auto2h (every 2h): SILENT while healthy. Unhealthy: loud on the first
#   run, quieter updates on every run after that until recovery, and one
#   RECOVERED notice.
# weekly (Mon 09:00): always sends the weekly summary.
set -uo pipefail

# Settings from the environment
STATUS_LOG="${STATUS_LOG:-/home/yashar/logs/storagebox-bisync.log}"
STATUS_SEND_DEFAULT="/home/yashar/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh"
STATUS_SEND="${STATUS_SEND:-$STATUS_SEND_DEFAULT}"
STATUS_MARKER="${STATUS_MARKER:-/home/yashar/logs/.sync-unhealthy}"
STATUS_MAX_AGE_HOURS="${STATUS_MAX_AGE_HOURS:-12}"
STATUS_SNAPSHOT_BYTES="${STATUS_SNAPSHOT_BYTES:-209715200}"
STATUS_ENV="/home/yashar/.config/ailaw-pr-review/env"

# Globals filled by read_state
PASS_EXIT="" PASS_FAILED="" PASS_TIME=""
START_TIME="" IN_PROGRESS=0
PAIR_OK=0 PAIR_FAIL=0
COPIED=0
ERR_TAIL=0
PASSES_OK=0 PASSES_FAIL=0
LAST_LINE=""
REASON=""

# log snapshot and derived temp files, removed on exit (also on error)
TMP_FILES=()
cleanup() {
    if [[ ${#TMP_FILES[@]} -gt 0 ]]; then
        rm -f -- "${TMP_FILES[@]}"
    fi
}
trap cleanup EXIT

# is a bisync running now? STATUS_RUNNING=1/0 decides; unset -> pgrep
bisync_running() {
    case "${STATUS_RUNNING:-}" in
        1) return 0 ;;
        0) return 1 ;;
    esac
    pgrep -f 'rclone bisync' >/dev/null 2>&1
}

# ISO timestamp (first field) of a log line to epoch seconds
log_time() {
    date -d "${1%% *}" +%s 2>/dev/null || true
}

# read the log ONCE; every state value comes from one byte-bounded snapshot
read_state() {
    PASS_EXIT="" PASS_FAILED="" PASS_TIME=""
    START_TIME="" IN_PROGRESS=0
    PAIR_OK=0 PAIR_FAIL=0
    COPIED=0
    ERR_TAIL=0
    PASSES_OK=0 PASSES_FAIL=0
    LAST_LINE=""

    if [[ ! -f "$STATUS_LOG" || ! -s "$STATUS_LOG" ]]; then
        return 0
    fi

    local snap
    snap=$(mktemp)
    TMP_FILES=("$snap")
    tail -c "$STATUS_SNAPSHOT_BYTES" "$STATUS_LOG" > "$snap"

    # last completed pass
    local last_pass rest
    last_pass=$(grep -E 'pass exit=[0-9]+ failed=' "$snap" | tail -1)
    if [[ -n "$last_pass" ]]; then
        PASS_TIME="${last_pass%% *}"
        rest="${last_pass#* }"
        PASS_EXIT="${rest#pass exit=}"
        PASS_EXIT="${PASS_EXIT%% *}"
        PASS_FAILED="${rest#*failed=}"
    fi

    # last pass start; in progress when it comes after the last pass exit
    local start_line start_n exit_n
    start_n=""
    exit_n=""
    start_line=$(grep -nE ' pass start$' "$snap" | tail -1)
    if [[ -n "$start_line" ]]; then
        start_n="${start_line%%:*}"
        START_TIME="${start_line#*:}"
        START_TIME="${START_TIME%% *}"
    fi
    exit_n=$(grep -nE ' pass exit=[0-9]+ failed=' "$snap" | tail -1 | cut -d: -f1)
    if [[ -n "$start_n" && ( -z "$exit_n" || "$start_n" -gt "$exit_n" ) ]]; then
        IN_PROGRESS=1
    fi

    # pair outcomes and copies since the last pass start
    if [[ -n "$start_n" ]]; then
        local window
        window=$(mktemp)
        TMP_FILES+=("$window")
        tail -n +"$((start_n + 1))" "$snap" > "$window"
        PAIR_OK=$(grep -cE 'pair\[[^]]+\] exit=0([^0-9]|$)' "$window")
        PAIR_FAIL=$(grep -cE 'pair\[[^]]+\] exit=[1-9][0-9]*([^0-9]|$)' "$window")
        COPIED=$(grep -c ': Copied (' "$window")
    fi

    ERR_TAIL=$(tail -1000 "$snap" | grep -c ERROR)
    PASSES_OK=$(grep -cE 'pass exit=0 failed=' "$snap")
    PASSES_FAIL=$(grep -cE 'pass exit=[1-9][0-9]* failed=' "$snap")
    LAST_LINE=$(grep -E 'INFO|NOTICE|ERROR' "$snap" | tail -1 | cut -c12-100)
    return 0
}

# healthy: a clean pass completed within STATUS_MAX_AGE_HOURS; a running
# bisync never overrides a failed pass or a stale start
healthy() {
    REASON=""
    if [[ -z "$PASS_EXIT" ]]; then
        if [[ "$IN_PROGRESS" -eq 1 ]] && bisync_running; then
            return 0
        fi
        REASON="no completed pass yet"
        return 1
    fi
    if [[ "$PASS_EXIT" != "0" ]]; then
        REASON="last pass failed: $PASS_FAILED"
        return 1
    fi
    local start_epoch age_h
    start_epoch=$(log_time "$START_TIME")
    if [[ -z "$start_epoch" ]]; then
        REASON="no sync pass started"
        return 1
    fi
    age_h=$(( ( $(date +%s) - start_epoch ) / 3600 ))
    if [[ "$age_h" -ge "$STATUS_MAX_AGE_HOURS" ]]; then
        REASON="no sync pass started for ${age_h}h"
        return 1
    fi
    return 0
}

# the state block shared by the messages
snap() {
    local drive_free box_free
    drive_free=$(df -h /media/yashar/Backups 2>/dev/null | awk 'END{print $4}')
    box_free=$(df -h /mnt/StorageBox 2>/dev/null | awk 'END{print $4}')

    local pass_exit="none" pass_time="never" started="never"
    if [[ -n "$PASS_EXIT" ]]; then
        pass_exit="$PASS_EXIT"
        pass_time=$(date -d "$PASS_TIME" '+%Y-%m-%d %H:%M' 2>/dev/null)
        pass_time="${pass_time:-never}"
    fi
    if [[ -n "$START_TIME" ]]; then
        started=$(date -d "$START_TIME" '+%Y-%m-%d %H:%M' 2>/dev/null)
        started="${started:-never}"
        local age_h
        age_h=$(( ( $(date +%s) - $(log_time "$START_TIME") ) / 3600 ))
        started="$started (${age_h}h ago)"
    fi
    local failed="none"
    if [[ -n "$PASS_FAILED" ]]; then
        failed="$PASS_FAILED"
    fi
    local running="no"
    if bisync_running; then
        running="yes"
    fi

    echo "• last pass: exit=$pass_exit at $pass_time | pairs ok $PAIR_OK / failed $PAIR_FAIL
• failed pairs: $failed
• copied this pass: $COPIED files
• pass started: $started
• bisync running now: $running
• errors (last 1000 lines): $ERR_TAIL
• last log line: ${LAST_LINE:0:90}
• drive: ${drive_free:-?} free | box: ${box_free:-?} free"
}

# auto2h: silent while healthy; loud while unhealthy; one RECOVERED notice
auto2h() {
    if healthy; then
        if [[ -f "$STATUS_MARKER" ]]; then
            rm -f "$STATUS_MARKER"
            "$STATUS_SEND" "✅ StorageBox sync RECOVERED — back to healthy. Weekly status resumes.
$(snap)"
        fi
    else
        if [[ -f "$STATUS_MARKER" ]]; then
            # repeat alert while unhealthy: same message, not loud
            "$STATUS_SEND" "❌ StorageBox sync UNHEALTHY (bi-hourly updates until recovery):
reason: $REASON
$(snap)"
        else
            touch "$STATUS_MARKER"
            "$STATUS_SEND" --loud "❌ StorageBox sync UNHEALTHY (bi-hourly updates until recovery):
reason: $REASON
$(snap)"
        fi
    fi
}

# weekly: always sends one message
weekly() {
    if healthy; then
        "$STATUS_SEND" "📅 StorageBox sync weekly status:
• state: healthy (aligned)
• recent passes: $PASSES_OK clean / $PASSES_FAIL failed
$(snap)"
    else
        "$STATUS_SEND" --loud "📅 StorageBox sync weekly status: UNHEALTHY — bi-hourly updates active.
• recent passes: $PASSES_OK clean / $PASSES_FAIL failed
$(snap)"
    fi
}

main() {
    local mode="${1:-auto2h}"
    if [[ -f "$STATUS_ENV" ]]; then
        set -a
        source "$STATUS_ENV"
        set +a
    fi
    read_state
    case "$mode" in
        auto2h) auto2h ;;
        weekly) weekly ;;
    esac
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
