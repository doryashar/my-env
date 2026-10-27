#!/usr/bin/env bash
# WhatsApp Backup: Syncthing receive dirs -> Hetzner StorageBox via rclone
# Sources:  ~/syncthing/whatsapp/{old,new}/{databases,media,backups}
#           (fed by phone Syncthing; old = previous phone, new = current phone)
# Databases: daily dated snapshot of msgstore.db.crypt1[45], GFS rotation
#            7 daily + 4 weekly + 3 monthly (per phone)
# Media:     full mirror, never rotated (content)
# Backups:   full mirror (E2E key material + settings, small)
set -uo pipefail

BASE="$HOME/syncthing/whatsapp"
RBASE="hetzner-storagebox:backup/whatsapp"
STAMP="$(date +%F)"
FAIL=""

for PHONE in old new; do
  SRC="$BASE/$PHONE"
  [ -d "$SRC" ] || { echo "[$PHONE] SKIP: $SRC missing"; continue; }

  # --- 1. media: full mirror (no rotation — irreplaceable content) ---
  # [new] media is excepted: its syncthing folder writes DIRECTLY into the
  # StorageBox mount (/mnt/storagebox) — mirroring an empty local dir would
  # DELETE the box copies. [old] media still lives locally.
  if [ "$PHONE" = "new" ]; then
    echo "[$PHONE] media: skipped (synced directly to StorageBox via mount)"
  elif [ -d "$SRC/media" ] && [ -n "$(find "$SRC/media" -type f -print -quit)" ]; then
    if ! rclone sync "$SRC/media" "$RBASE/$PHONE/media" --transfers 4 --checkers 8 \
         --stats-one-line --log-level WARNING 2>&1; then
      FAIL="${FAIL:+$FAIL; }[$PHONE] media sync failed"
    else
      echo "[$PHONE] media: mirrored ($(du -sh "$SRC/media" | cut -f1))"
    fi
  else
    echo "[$PHONE] media: nothing to sync yet"
  fi

  # --- 2. backups: full mirror (E2E keys, settings — small) ---
  if [ -d "$SRC/backups" ] && [ -n "$(find "$SRC/backups" -type f -print -quit)" ]; then
    if ! rclone sync "$SRC/backups" "$RBASE/$PHONE/backups" --transfers 4 --checkers 8 \
         --stats-one-line --log-level WARNING 2>&1; then
      FAIL="${FAIL:+$FAIL; }[$PHONE] backups sync failed"
    else
      echo "[$PHONE] backups: mirrored"
    fi
  else
    echo "[$PHONE] backups: nothing to sync yet"
  fi

  # --- 3. databases: dated snapshot of the live store (crypt15 preferred) ---
  RDB="$RBASE/$PHONE/databases"
  DB=""
  for cand in msgstore.db.crypt15 msgstore.db.crypt14; do
    [ -f "$SRC/databases/$cand" ] && { DB="$cand"; break; }
  done
  if [ -n "$DB" ]; then
    EXT="${DB##*.}"   # crypt14 / crypt15
    if ! rclone copyto "$SRC/databases/$DB" "$RDB/msgstore-$STAMP.$EXT" 2>&1; then
      FAIL="${FAIL:+$FAIL; }[$PHONE] db upload failed"
    else
      SIZE=$(stat -c%s "$SRC/databases/$DB")
      echo "[$PHONE] db: msgstore-$STAMP.$EXT ($SIZE bytes) uploaded"
    fi
  else
    echo "[$PHONE] db: no msgstore yet"
  fi

  # --- 4. GFS retention on msgstore-YYYY-MM-DD.crypt1[45]: 7d + 4w + 3m ---
  mapfile -t FILES < <(rclone lsf "$RDB" --files-only --include "msgstore-*.crypt1[45]" 2>/dev/null | sort -r)
  KEEP_DAILY=7; KEEP_WEEKLY=4; KEEP_MONTHLY=3
  kept_d=0; kept_w=0; kept_m=0; removed=0
  declare -A SEEN_W SEEN_M
  for f in "${FILES[@]:-}"; do
    [ -z "$f" ] && continue
    d="${f#msgstore-}"; d="${d%.*}"
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
  echo "[$PHONE] retention: kept $kept_d daily + $kept_w weekly + $kept_m monthly, removed $removed"
done

if [ -n "$FAIL" ]; then echo "ERROR: $FAIL"; exit 1; fi
echo "OK"
