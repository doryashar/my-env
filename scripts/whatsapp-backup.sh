#!/usr/bin/env bash
# WhatsApp Backup: Syncthing receive dirs -> Hetzner StorageBox via rclone
# Sources:  ~/syncthing/whatsapp/{databases,media}  (fed by phone Syncthing)
# Databases: daily dated snapshot of msgstore.db.crypt15, GFS rotation 7 daily + 4 weekly + 3 monthly
# Media:     full mirror, never rotated (content)
set -uo pipefail

SRC_DB="$HOME/syncthing/whatsapp/databases"
SRC_MEDIA="$HOME/syncthing/whatsapp/media"
RDB="hetzner-storagebox:backup/whatsapp/databases"
RMEDIA="hetzner-storagebox:backup/whatsapp/media"
STAMP="$(date +%F)"
FAIL=""

[ -d "$SRC_DB" ] || { echo "SKIP: $SRC_DB missing (phone not paired yet?)"; }

# --- 1. media: full mirror (no rotation — irreplaceable content) ---
if [ -d "$SRC_MEDIA" ] && find "$SRC_MEDIA" -type f | head -1 | grep -q .; then
  if ! rclone sync "$SRC_MEDIA" "$RMEDIA" --transfers 4 --checkers 8 --stats-one-line \
       --log-level WARNING 2>&1; then
    FAIL="media sync failed"
  fi
else
  echo "media: nothing to sync yet"
fi

# --- 2. databases: dated snapshot of the live crypt15 ---
if [ -f "$SRC_DB/msgstore.db.crypt15" ]; then
  if ! rclone copyto "$SRC_DB/msgstore.db.crypt15" \
       "$RDB/msgstore-$STAMP.crypt15" 2>&1; then
    FAIL="${FAIL:+$FAIL; }db upload failed"
  else
    SIZE=$(stat -c%s "$SRC_DB/msgstore.db.crypt15")
    echo "db: msgstore-$STAMP.crypt15 ($SIZE bytes) uploaded"
  fi
else
  echo "db: no msgstore.db.crypt15 yet"
fi

# --- 3. GFS retention on msgstore-YYYY-MM-DD.crypt15: 7d + 4w + 3m ---
mapfile -t FILES < <(rclone lsf "$RDB" --files-only --include "msgstore-*.crypt15" 2>/dev/null | sort -r)
KEEP_DAILY=7; KEEP_WEEKLY=4; KEEP_MONTHLY=3
kept_d=0; kept_w=0; kept_m=0; removed=0
declare -A SEEN_W SEEN_M
for f in "${FILES[@]:-}"; do
  [ -z "$f" ] && continue
  d="${f#msgstore-}"; d="${d%.crypt15}"
  # shellcheck disable=SC2034
  ep=$(date -d "$d" +%s 2>/dev/null) || continue
  week=$(date -d "$d" +%G-W%V); month="${d:0:7}"
  keep=false
  if [ "$kept_d" -lt "$KEEP_DAILY" ]; then keep=true; kept_d=$((kept_d+1));
  elif [ -z "${SEEN_W[$week]:-}" ] && [ "$kept_w" -lt "$KEEP_WEEKLY" ]; then keep=true; kept_w=$((kept_w+1)); SEEN_W[$week]=1
  elif [ -z "${SEEN_M[$month]:-}" ] && [ "$kept_m" -lt "$KEEP_MONTHLY" ]; then keep=true; kept_m=$((kept_m+1)); SEEN_M[$month]=1
  fi
  if ! $keep; then
    rclone delete "$RDB/$f" 2>/dev/null && removed=$((removed+1))
  fi
done
echo "retention: kept $kept_d daily + $kept_w weekly + $kept_m monthly, removed $removed"

if [ -n "$FAIL" ]; then echo "ERROR: $FAIL"; exit 1; fi
echo "OK"
