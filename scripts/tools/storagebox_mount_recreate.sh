#!/usr/bin/env bash
# Recreate the StorageBox rclone mount containers with:
#   - fail-fast rclone timeouts (no more eternal FUSE hangs)
#   - a Docker HEALTHCHECK probing the SMB backend directly
#
# The host mountpoints ~/mnt/hetzner-storagebox__{,__backup} are
# bind-mounted into the container at /data with :shared propagation,
# so the FUSE mount rclone creates on /data appears on the host.
#
# Recovery runbook: docs/troubleshooting-stuck-zsh-fuse.md

set -euo pipefail

MOUNT_BASE="/home/yashar/mnt"
RCLONE_IMAGE="rclone/rclone"
RESTART_POLICY="unless-stopped"

# Fail-fast backend timeouts (was: defaults, i.e. ~5m+ of wedged I/O)
EXTRA_RCLONE_FLAGS=(
  --contimeout=10s
  --timeout=60s
)

HEALTH_CMD='rclone lsf --contimeout 5s --timeout 15s hetzner-storagebox: --max-depth 1'

COMMON_MOUNT_ARGS=(
  --vfs-cache-mode full
  --vfs-cache-max-size 100G
  --vfs-cache-max-age 240h
  --buffer-size 256M
  --vfs-read-ahead 512M
  --vfs-read-chunk-size 32M
  --vfs-read-chunk-size-limit 1G
  --dir-cache-time 240h
  --poll-interval 15s
  --attr-timeout 1s
  --vfs-cache-poll-interval 15s
  --umask 022
  --uid 1000
  --gid 1000
  --metadata
  --cache-dir=/cache/hetzner-storagebox
  --allow-non-empty
  --log-file /cache/hetzner-storagebox.log
)

recreate_container() {
  local name="$1"
  local remote="$2"
  local host_data="$3"
  local encrypted_bind="$4"

  echo ">>> Recreating $name (remote: $remote)"

  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    docker rm -f "$name" >/dev/null
  fi

  # Detach any leftover FUSE mount on the bind source; docker refuses to
  # create the bind mount when the source path is a mountpoint (mkdir
  # returns EEXIST). Lazy detach is safe and instant. NB: mountpoint(1)
  # is useless here — a dead fuse mount returns ENOTCONN and reads as
  # "not a mountpoint" — so grep /proc/self/mounts instead.
  if grep -qs " $host_data " /proc/self/mounts; then
    fusermount3 -uz "$host_data" 2>/dev/null \
      || sudo -n umount -l "$host_data" 2>/dev/null || true
    sleep 1
  fi

  docker run -d \
    --name "$name" \
    --restart "$RESTART_POLICY" \
    --device /dev/fuse \
    --cap-add SYS_ADMIN \
    --security-opt apparmor=unconfined \
    --user "$(id -u):$(id -g)" \
    -v "/etc/passwd:/etc/passwd:ro" \
    -v "/etc/group:/etc/group:ro" \
    -v "/home/yashar/env/private/config/rclone:/config/rclone:ro" \
    -v "$MOUNT_BASE/rclone-cache:/cache" \
    -v "$encrypted_bind:/encrypted" \
    -v "$host_data:/data:shared" \
    --health-cmd "$HEALTH_CMD" \
    --health-interval 1m \
    --health-timeout 20s \
    --health-retries 3 \
    --health-start-period 30s \
    "$RCLONE_IMAGE" \
    mount "$remote" /data \
    "${COMMON_MOUNT_ARGS[@]}" \
    "${EXTRA_RCLONE_FLAGS[@]}" >/dev/null

  echo "    started: $name"
}

main() {
  recreate_container \
    "rclone-mount-hetzner-storagebox__" \
    "hetzner-storagebox:/" \
    "$MOUNT_BASE/hetzner-storagebox__" \
    "/home/yashar/env/private_encrypted"

  recreate_container \
    "rclone-mount-hetzner-storagebox__backup" \
    "hetzner-storagebox:/backup" \
    "$MOUNT_BASE/hetzner-storagebox__backup" \
    "/private_encrypted"

  echo ">>> Waiting for mounts to come up..."
  sleep 8

  for mp in hetzner-storagebox__ hetzner-storagebox__backup; do
    if grep -qs " $MOUNT_BASE/$mp " /proc/self/mounts; then
      echo "    OK: $MOUNT_BASE/$mp is mounted"
    else
      echo "    WARN: $MOUNT_BASE/$mp not mounted yet (check: docker logs)" >&2
    fi
  done

  echo ">>> Done. Health status (may show 'starting' for ~30s):"
  docker ps --format '{{.Names}}\t{{.Status}}' | grep rclone-mount || true
}

main "$@"
