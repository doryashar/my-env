#!/usr/bin/env bash
# bisync-run.sh — runs StorageBox bisync as PER-TREE pairs (bounded memory:
# a 10M-file single pair once ballooned to 23GB RAM and killed the session).
# Each pair gets its own listings (keyed by path). Pairs that have completed
# a run successfully are registered in $B/storagebox-pairs.txt and run
# regular; unregistered pairs are initialised once with --resync (with a
# remote mkdir for sub pairs). System directories are never synced. An
# explicit --resync re-baselines every pair. Extra args pass through.
# The merkle check runs from storagebox-merkle.timer.
set -u
RCLONE="${RCLONE:-/usr/local/bin/rclone}"
RCF="${RCF:-${RCLONE_CONFIG:-/home/yashar/.config/rclone/rclone.conf}}"
L1="${L1:-${BISYNC_LOCAL:-/media/yashar/Backups}}"
LOG="${LOG:-${BISYNC_LOG:-/home/yashar/logs/storagebox-bisync.log}}"
LOCK="${LOCK:-${BISYNC_LOCK:-/run/user/1000/storagebox-bisync.lock}}"
B="${B:-${BISYNC_WORKDIR:-$HOME/.cache/rclone/bisync}}"
REMOTE="${REMOTE:-${BISYNC_REMOTE:-hetzner-sftp:}}"
BISYNC_MOUNT_CHECK="${BISYNC_MOUNT_CHECK:-/home/yashar/storagebox-sync/mount-check.sh}"
BISYNC_LOG_MAX_BYTES="${BISYNC_LOG_MAX_BYTES:-209715200}"
REGISTRY="$B/storagebox-pairs.txt"

# --only-pair NAME: run a single pair ('.' = the root pair). Stripped from
# the arguments before anything is passed to rclone.
ONLY_PAIR=""
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --only-pair)
            if [ $# -ge 2 ]; then
                ONLY_PAIR="$2"
                shift 2
            else
                echo "Error: --only-pair requires a pair name" >&2
                exit 2
            fi
            ;;
        --only-pair=*)
            ONLY_PAIR="${1#--only-pair=}"
            shift
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done
set -- "${ARGS[@]}"

if [ -n "$ONLY_PAIR" ] && [ "$ONLY_PAIR" != "." ] && [ ! -d "$L1/$ONLY_PAIR" ]; then
    echo "Error: no such pair '$ONLY_PAIR'" >&2
    exit 2
fi

mkdir -p "$(dirname "$LOG")"
exec 9>"$LOCK"
if ! flock -n 9; then
    echo "$(date -Is) another bisync already running, skipping" >> "$LOG"
    exit 0
fi

# rotate the log if it grew past BISYNC_LOG_MAX_BYTES
if [ -f "$LOG" ] && [ "$(stat -c%s "$LOG")" -gt "$BISYNC_LOG_MAX_BYTES" ]; then
    mv -f "$LOG.2" "$LOG.3" 2>/dev/null || true
    mv -f "$LOG.1" "$LOG.2" 2>/dev/null || true
    mv -f "$LOG" "$LOG.1" 2>/dev/null || true
fi

"$BISYNC_MOUNT_CHECK" || exit 7

echo "$(date -Is) pass start" >> "$LOG"

pair() {  # pair <subdir-or-'.'> [extra flags...]
    local sub="$1"; shift
    local p1 p2 mode=()
    if [ "$sub" = "." ]; then
        p1="$L1" p2="${REMOTE}/"
        # root pair: files only (dirs are owned by their own pairs)
        set -- --filter "- /*/" "$@"
    else
        p1="$L1/$sub" p2="${REMOTE}/$sub"
    fi
    # backup pair: server-managed whatsapp pipeline writes live here (syncthing
    # + nightly backup cron). 86K+ files of churn/.tmp renames abort bisync
    # (--max-delete) and it must NOT mirror 100GB of phone media to the HDD.
    if [ "$sub" = "backup" ]; then
        set -- --filter "- /whatsapp/**" "$@"
    fi
    # Pairs that completed successfully are in the registry and run regular.
    # Unregistered pairs are initialised once with --resync; an explicit
    # --resync in "$@" re-baselines every pair.
    local in_registry=0 resync_explicit=0 a
    if [ -f "$REGISTRY" ] && grep -qxF -- "$sub" "$REGISTRY"; then
        in_registry=1
    fi
    for a in "$@"; do
        [ "$a" = "--resync" ] && resync_explicit=1
    done
    if [ "$resync_explicit" -eq 1 ]; then
        mode=(--resync)
    elif [ "$in_registry" -eq 0 ]; then
        if [ "$sub" != "." ]; then
            "$RCLONE" mkdir "$p2" --config "$RCF" >/dev/null 2>&1 || true
        fi
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
        --log-file "$LOG" --log-level INFO --workdir "$B" "${mode[@]}" "$@"
    local rc=$?
    echo "$(date -Is) pair[$sub] exit=$rc" >> "$LOG"
    if [ "$rc" -ne 0 ]; then
        return "$rc"
    fi
    if [ "$in_registry" -eq 0 ]; then
        echo "$sub" >> "$REGISTRY"
    fi
    return 0
}

FAIL=0
FAILED_PAIRS=()
if [ -n "$ONLY_PAIR" ]; then
    pair_list=("$ONLY_PAIR")
else
    pair_list=()
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        pair_list+=("$d")
    done < <(find "$L1" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
    pair_list+=(".")
fi

for sub in "${pair_list[@]}"; do
    case "$sub" in
        'System Volume Information'|'$RECYCLE.BIN'|"F:\$RECYCLE.BIN"|"lost+found"|".Trash-"*|".fseventsd"*|".Spotlight-V100"*)
            echo "$(date -Is) pair[$sub] skipped (system directory)" >> "$LOG"
            continue
            ;;
    esac
    pair "$sub" "$@" || { FAIL=1; FAILED_PAIRS+=("$sub"); }
done

failed_list=""
for sub in "${FAILED_PAIRS[@]}"; do
    if [ -z "$failed_list" ]; then
        failed_list="$sub"
    else
        failed_list="$failed_list,$sub"
    fi
done
echo "$(date -Is) pass exit=$FAIL failed=$failed_list" >> "$LOG"

# the merkle check runs from storagebox-merkle.timer
exit "$FAIL"
