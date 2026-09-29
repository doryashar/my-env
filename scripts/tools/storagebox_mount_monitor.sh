#!/usr/bin/env bash
# StorageBox mount health monitor: probe, alert, self-heal.
#
# Runs from storagebox-mount-monitor.timer (systemd --user) every 5 min.
#   1. Probes both FUSE mounts with a backgrounded ls (a wedged mount
#      can never be probed in the foreground or THIS script freezes).
#   2. Reads the container Docker health status.
#   3. On failure: sends a Telegram alert (if creds available) and
#      attempts recovery (container restart; fusermount detach + restart
#      if needed). Set RECOVER=0 to alert only.
#
# Runbook background: docs/troubleshooting-stuck-zsh-fuse.md

set -uo pipefail

MOUNT_BASE="/home/yashar/mnt"
PROBE_WAIT="${PROBE_WAIT:-10}"
RECOVER="${RECOVER:-1}"
CONT_MAIN="rclone-mount-hetzner-storagebox__"
CONT_BACKUP="rclone-mount-hetzner-storagebox__backup"

log() { echo "[storagebox-monitor] $*"; }

# Probe a mount without ever blocking: background ls + bounded wait.
# Echoes "ok" or "fail". NB: the done-marker must live in a fresh temp
# DIR (mktemp -d) — a mktemp FILE pre-exists, which would make the
# existence check pass instantly and race the ls (classic bug).
probe_mount() {
  local path="$1"
  local tmp_dir done_file
  tmp_dir=$(mktemp -d) || { echo "fail"; return; }
  done_file="$tmp_dir/done"
  ( ls "$path" >/dev/null 2>&1; echo "rc=$?" >"$done_file" ) &
  local waited=0
  while [ "$waited" -lt "$PROBE_WAIT" ]; do
    [ -f "$done_file" ] && break
    sleep 1
    waited=$((waited + 1))
  done
  if [ -f "$done_file" ] && grep -q '^rc=0$' "$done_file"; then
    rm -rf "$tmp_dir"
    echo "ok"
  else
    rm -rf "$tmp_dir"
    echo "fail"
  fi
}

container_health() {
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$1" 2>/dev/null || echo "missing"
}

notify() {
  local message="$1"
  # Telegram creds (TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID) live in the
  # private secrets file, which uses shell syntax -> source it.
  local secrets="${SECRETS_FILE:-$HOME/env/tmp/private/secrets}"
  # shellcheck disable=SC1090
  [ -f "$secrets" ] || secrets="$HOME/private/secrets"
  if [ -f "$secrets" ]; then
    # shellcheck disable=SC1090
    source "$secrets" 2>/dev/null || true
  fi
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    local payload
    payload=$(jq -nc --arg chat_id "$TELEGRAM_CHAT_ID" \
      --arg text "$message" \
      '{chat_id:$chat_id, text:$text}' 2>/dev/null) || return 0
    local tmp
    tmp=$(mktemp)
    printf '%s' "$payload" >"$tmp"
    curl -s --max-time 10 -X POST \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -H 'Content-Type: application/json' \
      --data-binary @"$tmp" >/dev/null 2>&1 || true
    rm -f "$tmp"
  else
    log "ALERT (no telegram creds): $message"
  fi
}

restart_containers() {
  log "restarting mount containers..."
  docker restart "$CONT_MAIN" "$CONT_BACKUP" >/dev/null 2>&1 || true
  sleep 8
}

detach_dead_mounts() {
  # Lazy-detach wedged FUSE mountpoints so the container restart can
  # bind-mount fresh sources. Works unprivileged for uid-1000 mounts.
  # NB: detect via /proc/self/mounts; mountpoint(1) misreports dead
  # fuse mounts (ENOTCONN) as "not a mountpoint".
  for mp in "$MOUNT_BASE/hetzner-storagebox__" "$MOUNT_BASE/hetzner-storagebox__backup"; do
    if grep -qs " $mp " /proc/self/mounts; then
      fusermount3 -uz "$mp" 2>/dev/null || sudo -n umount -l "$mp" 2>/dev/null || true
      log "detached $mp"
    fi
  done
}

recover() {
  local failing="$1"
  notify "StorageBox mount FAILURE on $failing - attempting auto-recovery"

  # Detach any dead FUSE mountpoints FIRST: docker restart/start fails
  # with "mkdir ...: file exists" while a corpse mount occupies the
  # bind source path.
  detach_dead_mounts
  restart_containers

  local still_bad=0
  for mp in hetzner-storagebox__ hetzner-storagebox__backup; do
    [ "$(probe_mount "$MOUNT_BASE/$mp")" = "fail" ] && still_bad=1
  done

  if [ "$still_bad" -eq 1 ]; then
    log "still unhealthy after restart; retrying detach + restart"
    detach_dead_mounts
    restart_containers
    still_bad=0
    for mp in hetzner-storagebox__ hetzner-storagebox__backup; do
      [ "$(probe_mount "$MOUNT_BASE/$mp")" = "fail" ] && still_bad=1
    done
  fi

  if [ "$still_bad" -eq 0 ]; then
    notify "StorageBox mounts RECOVERED ($failing). Containers restarted."
  else
    notify "StorageBox mounts STILL DOWN after auto-recovery. Manual fix needed: docs/troubleshooting-stuck-zsh-fuse.md"
  fi
}

main() {
  local failures=0
  for mp in hetzner-storagebox__ hetzner-storagebox__backup; do
    local result health
    result=$(probe_mount "$MOUNT_BASE/$mp")
    health=$(container_health "rclone-mount-$mp")
    log "$mp: probe=$result container_health=$health"
    [ "$result" = "fail" ] && failures=$((failures + 1))
  done

  if [ "$failures" -gt 0 ]; then
    if [ "$RECOVER" = "1" ]; then
      recover "$failures mount(s)"
    else
      notify "StorageBox mount FAILURE detected ($failures). RECOVER=0 - no auto-recovery attempted."
    fi
    exit 1
  fi
  exit 0
}

main "$@"
