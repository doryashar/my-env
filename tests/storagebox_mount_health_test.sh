#!/usr/bin/env bash
# Test: StorageBox rclone FUSE mounts are responsive.
#
# Regression test for the 2026-09-26 incident where a wedged rclone
# FUSE mount put every shell that touched it into uninterruptible
# (D-state) sleep, making terminals appear frozen.
#
# See docs/troubleshooting-stuck-zsh-fuse.md for the full runbook.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

MOUNT_HEALTH_TIMEOUT="${MOUNT_HEALTH_TIMEOUT:-10}"

assert_mount_responds() {
  local mount_path="$1"
  local message="${2:-Mount $mount_path should respond within ${MOUNT_HEALTH_TIMEOUT}s}"

  # Run ls in background so a wedged (D-state) mount cannot block the
  # test forever; we only check on it for a bounded time. If it hangs,
  # the background ls stays stuck (harmless) and the assertion fails.
  local out_file
  out_file=$(mktemp)
  ( ls "$mount_path" >"$out_file" 2>&1; echo "rc=$?" >"$out_file.done" ) &

  local waited=0
  while [ "$waited" -lt "$MOUNT_HEALTH_TIMEOUT" ]; do
    [ -f "$out_file.done" ] && break
    sleep 1
    waited=$((waited + 1))
  done

  if [ -f "$out_file.done" ] && grep -q '^rc=0$' "$out_file.done"; then
    echo -e "${GREEN}✓${NC} $message"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
  else
    echo -e "${RED}✗${NC} $message (unresponsive or error after ${waited}s)"
    echo -e "${RED}  ${NC} output: $(head -2 "$out_file" 2>/dev/null)"
    echo -e "${YELLOW}  Follow docs/troubleshooting-stuck-zsh-fuse.md to recover${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
  fi

  rm -f "$out_file" "$out_file.done"
}

assert_mount_exists() {
  local mount_path="$1"
  local message="${2:-FUSE mount $mount_path should exist}"
  if findmnt -t fuse.rclone -no TARGET | grep -qx "$mount_path"; then
    echo -e "${GREEN}✓${NC} $message"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
  else
    echo -e "${RED}✗${NC} $message"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
  fi
}

echo -e "${BLUE}=== StorageBox mount health tests ===${NC}"

assert_mount_exists "/home/yashar/mnt/hetzner-storagebox__" \
  "Main StorageBox mount is registered"
assert_mount_exists "/home/yashar/mnt/hetzner-storagebox__backup" \
  "Backup StorageBox mount is registered"

assert_mount_responds "/home/yashar/mnt/hetzner-storagebox__" \
  "Main StorageBox mount responds"
assert_mount_responds "/home/yashar/mnt/hetzner-storagebox__backup" \
  "Backup StorageBox mount responds"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^rclone-mount-hetzner-storagebox__$'; then
    assert_equals "0" "0" "rclone main mount container is running"
else
    assert_equals "running" "stopped" "rclone main mount container is running"
fi

echo -e "${BLUE}--- Prevention layer ---${NC}"

for cont in rclone-mount-hetzner-storagebox__ rclone-mount-hetzner-storagebox__backup; do
    if docker inspect -f '{{if .Config.Healthcheck}}yes{{else}}no{{end}}' "$cont" 2>/dev/null | grep -q yes; then
        assert_equals "0" "0" "$cont has a Docker HEALTHCHECK"
    else
        assert_equals "healthcheck" "missing" "$cont has a Docker HEALTHCHECK"
    fi
done

ENV_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
for script in storagebox_mount_monitor.sh storagebox_mount_recreate.sh; do
    if [ -x "$ENV_ROOT/scripts/tools/$script" ]; then
        assert_equals "0" "0" "scripts/tools/$script is executable"
    else
        assert_equals "executable" "missing" "scripts/tools/$script is executable"
    fi
done

if systemctl --user is-active storagebox-mount-monitor.timer &>/dev/null; then
    assert_equals "0" "0" "storagebox-mount-monitor.timer is active"
else
    assert_equals "active" "inactive" "storagebox-mount-monitor.timer is active"
fi

echo -e "${BLUE}Tests run: ${TESTS_RUN}, passed: ${TESTS_PASSED}, failed: ${TESTS_FAILED}${NC}"
if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
