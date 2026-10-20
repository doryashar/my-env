#!/usr/bin/env bash
# merkle-snap.sh [root] — per-directory aggregate "picture" of a tree.
# Each run walks files (stat only, no content reads), rolls up per-dir
# {count, bytes, max mtime}, diffs against the previous picture and alerts
# on suspicious shrinkage (silent corruption / mass deletion tripwire).
# Exit: 0 normal, 3 suspicious shrink (alert sent), 1 hard error.
# MERKLE_NO_TG=1 suppresses telegram (tests). Snapshot refreshes after diff.
set -u
ROOT="${1:-/media/yashar/Backups}"
SNAP_DIR=/home/yashar/logs/merkle
SNAP="$SNAP_DIR/snap-$(printf %s "$ROOT" | md5sum | cut -c1-8).tsv"
DIFF_OUT="$SNAP_DIR/diff-latest.txt"
mkdir -p "$SNAP_DIR"

tmp_new=$(mktemp "$SNAP_DIR/.walk.XXXXXX")
find "$ROOT" -type f -printf '%h\t%s\t%T@\n' 2>/dev/null | \
    awk -F'\t' '{c[$1]++; b[$1]+=$2; if ($3+0 > m[$1]+0) m[$1]=$3}
        END {for (d in c) printf "%s\t%d\t%d\t%.0f\n", d, c[d], b[d], m[d]}' | sort > "$tmp_new"

if [ ! -s "$SNAP" ]; then
    mv "$tmp_new" "$SNAP"
    echo "$(date -Is) baseline picture created: $(wc -l < "$SNAP") dirs" >> "$SNAP_DIR/merkle.log"
    exit 0
fi

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
' "$SNAP" "$tmp_new" > "$DIFF_OUT"

read -r added removed changed files_lost bytes_lost < <(awk '
    /^ADDED/{a++; fl+=$3} /^REMOVED/{r++; fl-=$3; bl-=$4}
    /^CHANGED/{c++} END {print a+0, r+0, c+0, fl+0, bl+0}' "$DIFF_OUT")

mv "$tmp_new" "$SNAP"
echo "$(date -Is) diff: +$added -$removed ~$changed dirs, net files $files_lost, bytes $bytes_lost" >> "$SNAP_DIR/merkle.log"

suspicious=0
[ "$removed" -gt 0 ] && suspicious=1
[ "$files_lost" -lt -1000 ] && suspicious=1
[ "$bytes_lost" -lt -10000000000 ] && suspicious=1

if [ "$suspicious" -eq 1 ]; then
    summary=$(head -20 "$DIFF_OUT" | tr '\n' '|')
    if [ -z "${MERKLE_NO_TG:-}" ]; then
        set -a; source /home/yashar/.config/ailaw-pr-review/env; set +a
        /home/yashar/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh --loud \
            "🚨 Merkle tripwire: suspicious shrink on $ROOT — net $files_lost files / $bytes_lost bytes, $removed dirs removed. Top changes: $summary"
    fi
    exit 3
fi
exit 0
