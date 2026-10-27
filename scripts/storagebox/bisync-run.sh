#!/usr/bin/env bash
# bisync-run.sh — runs StorageBox bisync as PER-TREE pairs (bounded memory:
# a 10M-file single pair once ballooned to 23GB RAM and killed the session).
# Each pair gets its own listings (keyed by path). Pairs whose listings are
# missing are auto-initialized with --resync. Extra args pass through.
set -u
RCLONE=/usr/local/bin/rclone
RCF=/home/yashar/.config/rclone/rclone.conf
L1="/media/yashar/Backups"
LOG="/home/yashar/logs/storagebox-bisync.log"
LOCK="/run/user/1000/storagebox-bisync.lock"
B="$HOME/.cache/rclone/bisync"
mkdir -p "$(dirname "$LOG")"
exec 9>"$LOCK"
if ! flock -n 9; then
    echo "$(date -Is) another bisync already running, skipping" >> "$LOG"
    exit 0
fi

/home/yashar/storagebox-sync/mount-check.sh || exit 7

pair() {  # pair <subdir-or-'.'> [extra flags...]
    local sub="$1"; shift
    local p1 p2 esc1 esc2 mode=()
    if [ "$sub" = "." ]; then
        p1="$L1" p2="hetzner-sftp:/"
        # root pair: files only (dirs are owned by their own pairs)
        set -- --filter "- /*/" "$@"
    else
        p1="$L1/$sub" p2="hetzner-sftp:/$sub"
    fi
    # backup pair: server-managed whatsapp pipeline writes live here (syncthing
    # + nightly backup cron). 86K+ files of churn/.tmp renames abort bisync
    # (--max-delete) and it must NOT mirror 100GB of phone media to the HDD.
    if [ "$sub" = "backup" ]; then
        set -- --filter "- /whatsapp/**" "$@"
    fi
    esc1=$(printf %s "$p1" | md5sum | cut -c1-8)
    esc2=$(printf %s "$p2" | md5sum | cut -c1-8)
    if ! ls "$B"/*"${esc1}..${esc2}".path1.lst >/dev/null 2>&1; then
        mode=(--resync)
    fi
    echo "$(date -Is) pair[$sub] start ${mode[*]:-regular}" >> "$LOG"
    "$RCLONE" bisync "$p1" "$p2" --config "$RCF" \
        --conflict-resolve newer --conflict-loser num \
        --max-delete 25 --max-delete-size 10G \
        --max-transfer 200G \
        --max-lock 5m \
        --recover --resilient \
        --transfers 8 --checkers 8 --multi-thread-streams 1 \
        --retries 5 --low-level-retries 20 \
        --log-file "$LOG" --log-level INFO "${mode[@]}" "$@"
    local rc=$?
    echo "$(date -Is) pair[$sub] exit=$rc" >> "$LOG"
    [ "$rc" -ne 0 ] && return "$rc"
    return 0
}

FAIL=0
while IFS= read -r d; do
    [ -n "$d" ] || continue
    pair "$d" "$@" || FAIL=1
done < <(find "$L1" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
pair . "$@" || FAIL=1

if [ "$FAIL" -eq 0 ]; then
    ( /home/yashar/storagebox-sync/merkle-snap.sh >> /home/yashar/logs/merkle/merkle.log 2>&1 ) &
fi
exit "$FAIL"
