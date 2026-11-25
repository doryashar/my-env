#!/usr/bin/env bash
# Behavioural tests for scripts/whatsapp-backup.sh with a stub rclone.
#
# The stub emulates the StorageBox with a local directory ($T/box):
# remote paths "hetzner-storagebox:..." map to "$T/box/...", and every
# call's full argument list is appended to $T/rclone.args.
#
# Covers:
#   S1  first run: old's media/backups mirrors and new's backups mirror
#       land on the box; new's media is NOT mirrored (Syncthing writes
#       it to the Storage Box directly); every sync carries --backup-dir
#   S2  a local deletion is kept on the Box (moved to
#       _deleted/<media|backups>/<today>/), not erased
#   S2b an emptied local directory never erases the Box copy (the
#       mirror is skipped by the script's guard; nothing moves)
#   S3  GFS 7/4/3 retention is per phone (old phone's seen weeks/months
#       do not leak into new phone's bookkeeping)
#   S4  per-phone summary line

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export T

BASE="$T/home/syncthing/whatsapp"
BOX="$T/box/backup/whatsapp"
STAMP="$(date +%F)"
export HOME="$T/home"

# --- stub rclone ---------------------------------------------------------
mkdir -p "$T/bin"
cat > "$T/bin/rclone" <<'STUB'
#!/bin/bash
# Stub rclone: emulates the StorageBox remote with $T/box (local).
to_box() {
    case "$1" in
        hetzner-storagebox:*)
            printf '%s' "${1#hetzner-storagebox:}" | sed "s|^|$T/box/|"
            ;;
        *)
            printf '%s' "$1"
            ;;
    esac
}
log() {
    {
        printf 'rclone'
        local a
        for a in "$@"; do printf ' %s' "$a"; done
        printf '\n'
    } >> "$T/rclone.args"
}
case "$1" in
    sync)
        log "$@"
        src="$2"
        dest="$(to_box "$3")"
        backup=""
        i=4
        while [ "$i" -le $# ]; do
            if [ "${!i}" = "--backup-dir" ]; then
                j=$((i + 1))
                backup="$(to_box "${!j}")"
            fi
            i=$((i + 1))
        done
        mkdir -p "$dest"
        # copy all regular files from SRC to DEST
        while IFS= read -r -d '' f; do
            rel="${f#"$src"/}"
            mkdir -p "$(dirname "$dest/$rel")"
            cp "$f" "$dest/$rel"
        done < <(find "$src" -type f -print0 2>/dev/null)
        # files present in DEST but absent from SRC are moved to the
        # backup dir at the same relative path
        while IFS= read -r -d '' f; do
            rel="${f#"$dest"/}"
            if [ ! -f "$src/$rel" ]; then
                b="$backup/$rel"
                mkdir -p "$(dirname "$b")"
                mv "$f" "$b"
            fi
        done < <(find "$dest" -type f -print0 2>/dev/null)
        ;;
    copyto)
        log "$@"
        src="$2"
        dest="$(to_box "$3")"
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest"
        ;;
    lsf)
        dir="$(to_box "$2")"
        if [ -d "$dir" ]; then
            (cd "$dir" && find . -type f | sed 's|^\./||' | sort)
        fi
        ;;
    delete)
        rm -f "$(to_box "$2")"
        ;;
esac
exit 0
STUB
chmod +x "$T/bin/rclone"
export PATH="$T/bin:$PATH"

# --- fixtures -------------------------------------------------------------
mkdir -p "$T/home"
# old phone: media (incl. a sub dir), backups, one local msgstore
mkdir -p "$BASE/old/media/sub" "$BASE/old/backups" "$BASE/old/databases"
printf 'm1\n' > "$BASE/old/media/m1.jpg"
printf 'm2\n' > "$BASE/old/media/sub/m2.jpg"
printf 'bk1\n' > "$BASE/old/backups/bk1"
printf 'old-db\n' > "$BASE/old/databases/msgstore.db.crypt15"
# old phone on the box: three historical snapshots
mkdir -p "$BOX/old/databases"
for d in 2026-06-08 2026-06-10 2026-06-15; do
    printf 'snap\n' > "$BOX/old/databases/msgstore-$d.crypt15"
done
# new phone: media (incl. a sub dir), two backup files, one local msgstore
mkdir -p "$BASE/new/media/sub" "$BASE/new/backups" "$BASE/new/databases"
printf 'a\n' > "$BASE/new/media/a.jpg"
printf 'b\n' > "$BASE/new/media/sub/b.jpg"
printf 'key\n' > "$BASE/new/backups/key.crypt15"
printf 'settings\n' > "$BASE/new/backups/settings.json"
printf 'new-db\n' > "$BASE/new/databases/msgstore.db.crypt15"
# new phone on the box: nothing

# --- helpers ---------------------------------------------------------------
# dates present on the box for one phone's databases dir
box_dates() {
    ls "$BOX/$1/databases" 2>/dev/null \
        | sed 's|^msgstore-||; s|\.crypt1[45]$||' | sort
}

# Expected GFS survivors, mirroring the script's rule exactly: sort newest
# first; keep the first 7; then the first file of each of the next 4
# distinct ISO weeks not yet satisfied; then the first file of each of the
# next 3 distinct months not yet satisfied.
expected_keep() {
    local d week month
    local kept_d=0 kept_w=0 kept_m=0
    local kept=()
    local -A seen_w=() seen_m=()
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        week="$(date -d "$d" +%G-W%V)"
        month="${d:0:7}"
        if [ "$kept_d" -lt 7 ]; then
            kept_d=$((kept_d + 1))
            kept+=("$d")
        elif [ -z "${seen_w[$week]:-}" ] && [ "$kept_w" -lt 4 ]; then
            kept_w=$((kept_w + 1))
            seen_w["$week"]=1
            kept+=("$d")
        elif [ -z "${seen_m[$month]:-}" ] && [ "$kept_m" -lt 3 ]; then
            kept_m=$((kept_m + 1))
            seen_m["$month"]=1
            kept+=("$d")
        fi
    done < <(printf '%s\n' "$@" | sort -r)
    printf '%s\n' "${kept[@]}" | sort
}

run_script() {
    bash "$REPO/scripts/whatsapp-backup.sh"
}

# --- S1: first run ----------------------------------------------------------
echo "========================================"
echo "WhatsApp Backup Tests"
echo "========================================"
echo ""
echo "=== S1: first run ==="
out="$(run_script)"
assert_exit_code 0 $? "S1: first run exits 0"
assert_file_exists "$BOX/old/media/m1.jpg" \
    "S1: box has old/media/m1.jpg"
assert_file_exists "$BOX/old/media/sub/m2.jpg" \
    "S1: box has old/media/sub/m2.jpg"
assert_file_exists "$BOX/old/backups/bk1" \
    "S1: box has old/backups/bk1"
assert_file_exists "$BOX/new/backups/key.crypt15" \
    "S1: box has new/backups/key.crypt15"
assert_file_exists "$BOX/new/backups/settings.json" \
    "S1: box has new/backups/settings.json"
assert_file_exists "$BOX/new/databases/msgstore-$STAMP.crypt15" \
    "S1: box has new/databases/msgstore-<today>.crypt15"
assert_file_not_exists "$BOX/new/media/a.jpg" \
    "S1: new/media/a.jpg is NOT on the box (media skipped by design)"
sync_lines="$(grep -c '^rclone sync ' "$T/rclone.args")"
assert_equals 3 "$sync_lines" \
    "S1: rclone.args has exactly three sync lines"
sync_lines_missing="$(grep '^rclone sync ' "$T/rclone.args" \
    | grep -vc -- '--backup-dir' || true)"
assert_equals 0 "$sync_lines_missing" \
    "S1: every sync line carries --backup-dir"

# --- S2: local deletion kept on the box --------------------------------------
echo "=== S2: local deletion kept on the box ==="
rm -f "$BASE/old/media/m1.jpg" "$BASE/new/backups/key.crypt15"
out="$(run_script)"
assert_exit_code 0 $? "S2: run after local deletions exits 0"
assert_file_not_exists "$BOX/old/media/m1.jpg" \
    "S2: old/media/m1.jpg gone from its box location"
assert_file_not_exists "$BOX/new/backups/key.crypt15" \
    "S2: new/backups/key.crypt15 gone from its box location"
assert_file_exists "$BOX/old/_deleted/media/$STAMP/m1.jpg" \
    "S2: deleted media file kept under old/_deleted/media/<today>/"
assert_file_exists "$BOX/new/_deleted/backups/$STAMP/key.crypt15" \
    "S2: deleted backup file kept under new/_deleted/backups/<today>/"
assert_file_exists "$BOX/old/media/sub/m2.jpg" \
    "S2: old/media/sub/m2.jpg still in place"
assert_file_exists "$BOX/new/backups/settings.json" \
    "S2: new/backups/settings.json still in place"

# --- S2b: emptied directory never erases the box copy ------------------------
echo "=== S2b: emptied directory never erases the box copy ==="
rm -f "$BASE/old/backups/bk1"
out="$(run_script)"
assert_exit_code 0 $? "S2b: run after emptying old/backups exits 0"
assert_file_exists "$BOX/old/backups/bk1" \
    "S2b: old/backups/bk1 still at its original box location"
deleted_files="$(find "$BOX/old/_deleted/backups" -type f 2>/dev/null | wc -l)"
assert_equals 0 "$deleted_files" \
    "S2b: nothing written under old/_deleted/backups/"

# --- S3: per-phone retention --------------------------------------------------
echo "=== S3: per-phone retention ==="
rm -rf "$BOX/old/databases" "$BOX/new/databases"
mkdir -p "$BOX/old/databases" "$BOX/new/databases"
for d in 2026-06-08 2026-06-10 2026-06-15; do
    printf 'snap\n' > "$BOX/old/databases/msgstore-$d.crypt15"
done
printf 'snap\n' > "$BOX/old/databases/msgstore-$STAMP.crypt15"
for d in 2026-06-09 2026-06-11 2026-07-01 2026-07-15 \
         2026-08-01 2026-08-15 2026-09-01 2026-09-15 \
         2026-10-01 2026-10-15 2026-11-01 2026-11-10 \
         2026-11-15 2026-11-20 2026-11-22; do
    printf 'snap\n' > "$BOX/new/databases/msgstore-$d.crypt15"
done
printf 'snap\n' > "$BOX/new/databases/msgstore-$STAMP.crypt15"

out="$(run_script)"
assert_exit_code 0 $? "S3: retention run exits 0"
assert_equals \
    "$(expected_keep 2026-06-09 2026-06-11 2026-07-01 2026-07-15 \
       2026-08-01 2026-08-15 2026-09-01 2026-09-15 \
       2026-10-01 2026-10-15 2026-11-01 2026-11-10 \
       2026-11-15 2026-11-20 2026-11-22 "$STAMP")" \
    "$(box_dates new)" \
    "S3: new phone retains exactly the expected_keep set (GFS 7/4/3)"
assert_file_exists "$BOX/new/databases/msgstore-2026-06-11.crypt15" \
    "S3: 2026-06-11 survives (old phone has files in that ISO week)"

# --- S4: summary ---------------------------------------------------------------
echo "=== S4: summary ==="
# The old phone holds exactly 4 snapshots (3 fixture + today), all within
# the 7-daily cap, so its line reports kept 4 daily; the new phone
# (16 snapshots) hits the cap: kept 7 daily.
assert_contains "$out" "[old] retention: kept 4 daily" \
    "S4: old phone's summary reports kept 4 daily"
assert_contains "$out" "[new] retention: kept 7 daily" \
    "S4: new phone's summary reports kept 7 daily"

# --- results -----------------------------------------------------------------
if print_test_summary; then
    exit 0
fi
exit 1
