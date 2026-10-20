#!/usr/bin/env bash
# Verifies the boot-without-HDD fix configs (see docs/fix-boot-without-usb-hdd.md)
set -u
fail=0

check() {
  if eval "$2" >/dev/null 2>&1; then
    echo "PASS: $1"
  else
    echo "FAIL: $1"
    fail=1
  fi
}

check "GRUB cmdline blacklists simpledrm" \
  'grep -q "initcall_blacklist=sysfb_init" /etc/default/grub'
check "GRUB config regenerated with blacklist" \
  'grep -q "initcall_blacklist=sysfb_init" /boot/grub/grub.cfg'
check "Backups fstab entry has short device timeout" \
  'grep "Backups" /etc/fstab | grep -q "x-systemd.device-timeout=5s"'
check "Backups fstab entry still has nofail" \
  'grep "Backups" /etc/fstab | grep -q "nofail"'
check "StorageBox CIFS has _netdev,nofail" \
  'grep "StorageBox" /etc/fstab | grep -q "_netdev,nofail"'

exit $fail
