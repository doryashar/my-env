#!/usr/bin/env bash
# merkle-snap.sh [root] — per-directory aggregate "picture" of a tree.
# Each run walks files (stat only, no content reads), rolls up per-dir
# {count, bytes, max mtime}, diffs against the previous picture and alerts
# on suspicious shrinkage (silent corruption / mass deletion tripwire):
# a removed directory, a net loss of more than 1000 files or 10 GB of
# bytes (ADDED, REMOVED and CHANGED deltas are all counted), or a
# directory that still exists but dropped to zero files.
# Exit: 0 normal, 3 suspicious shrink (alert sent), 1 hard error.
# MERKLE_NO_TG=1 suppresses telegram (tests). Snapshot refreshes after diff.
set -u

MERKLE_SNAP_DIR="${MERKLE_SNAP_DIR:-/home/yashar/logs/merkle}"
MERKLE_SEND="${MERKLE_SEND:-/home/yashar/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh}"
MERKLE_ENV="/home/yashar/.config/ailaw-pr-review/env"

TMP_NEW=""

# the temporary walk file is removed on exit, even on error
cleanup() {
    if [[ -n "$TMP_NEW" ]]; then
        rm -f -- "$TMP_NEW"
    fi
}
trap cleanup EXIT

# one line per directory that has files: dir, count, bytes, max mtime
walk_tree() {
    find "$1" -type f -printf '%h\t%s\t%T@\n' 2>/dev/null | \
        awk -F'\t' '{c[$1]++; b[$1]+=$2; if ($3+0 > m[$1]+0) m[$1]=$3}
            END {for (d in c) printf "%s\t%d\t%d\t%.0f\n", d, c[d], b[d], m[d]}' | sort > "$TMP_NEW"
}

# diff previous picture against the new walk; ADDED/CHANGED/REMOVED lines
make_diff() {
    awk -F'\t' -v OFS='\t' '
        NR==FNR {pc[$1]=$2; pb[$1]=$3; pm[$1]=$4; next}
        {
            nc[$1]=$2; nb[$1]=$3; nm[$1]=$4
            if ($1 in pc) {
                if (pc[$1]!=$2 || pb[$1]!=$3 || pm[$1]!=$4) print "CHANGED", $1, pc[$1]"->"$2" files", pb[$1]"->"$3" bytes"
            } else print "ADDED", $1, $2" files", $3" bytes"
            delete pc[$1]; delete pb[$1]
        }
        END {for (d in pc) print "REMOVED", d, pc[d]" files", pb[d]" bytes"}
    ' "$1" "$2" > "$3"
}

# net sums over the diff; CHANGED lines contribute their a->b deltas
count_totals() {
    read -r ADDED REMOVED CHANGED FILES_LOST BYTES_LOST EMPTY_DROPS \
        < <(awk -F'\t' '
            /^ADDED/{a++; fl+=$3} /^REMOVED/{r++; fl-=$3; bl-=$4}
            /^CHANGED/{
                c++
                split($3, f, "->"); sub(/ files$/, "", f[2])
                split($4, y, "->"); sub(/ bytes$/, "", y[2])
                fl += f[2] - f[1]
                bl += y[2] - y[1]
                if (f[2] + 0 == 0) empty++
            }
            END {print a+0, r+0, c+0, fl+0, bl+0, empty+0}' "$1")
}

main() {
    local root="${1:-/media/yashar/Backups}"
    local snap diff_out
    snap="$MERKLE_SNAP_DIR/snap-$(printf %s "$root" | md5sum | cut -c1-8).tsv"
    diff_out="$MERKLE_SNAP_DIR/diff-latest.txt"
    mkdir -p "$MERKLE_SNAP_DIR"

    TMP_NEW=$(mktemp "$MERKLE_SNAP_DIR/.walk.XXXXXX")
    walk_tree "$root"

    if [ ! -s "$snap" ]; then
        mv "$TMP_NEW" "$snap"
        echo "$(date -Is) baseline picture created: $(wc -l < "$snap") dirs" \
            >> "$MERKLE_SNAP_DIR/merkle.log"
        exit 0
    fi

    make_diff "$snap" "$TMP_NEW" "$diff_out"
    count_totals "$diff_out"

    mv "$TMP_NEW" "$snap"
    local diff_line
    diff_line="diff: +$ADDED -$REMOVED ~$CHANGED dirs, net files $FILES_LOST"
    diff_line="$diff_line, bytes $BYTES_LOST"
    echo "$(date -Is) $diff_line" >> "$MERKLE_SNAP_DIR/merkle.log"

    local suspicious=0
    [ "$REMOVED" -gt 0 ] && suspicious=1
    [ "$FILES_LOST" -lt -1000 ] && suspicious=1
    [ "$BYTES_LOST" -lt -10000000000 ] && suspicious=1
    [ "$EMPTY_DROPS" -gt 0 ] && suspicious=1

    if [ "$suspicious" -eq 1 ]; then
        local summary msg
        summary=$(head -20 "$diff_out" | tr '\n' '|')
        msg="🚨 Merkle tripwire: suspicious shrink on $root — net $FILES_LOST"
        msg="$msg files / $BYTES_LOST bytes, $REMOVED dirs removed."
        msg="$msg Top changes: $summary"
        if [ -z "${MERKLE_NO_TG:-}" ]; then
            if [ -f "$MERKLE_ENV" ]; then
                set -a; source "$MERKLE_ENV"; set +a
            fi
            "$MERKLE_SEND" --loud "$msg"
        fi
        exit 3
    fi
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
