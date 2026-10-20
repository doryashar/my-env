# Dell U2412M cursor jitter — diagnosis

**Date:** 2026-09-30
**Symptom:** Cursor jumps/jitters when moving on the Dell U2412M only; the
5120x1440 ultrawide is smooth. Refresh rate showed 60Hz (actually 59.95 —
normal, not the cause).

## Root cause

The Dell's picture is running **through the DisplayLink DL-6950 USB dock**
(evdi `card3-HDMI-A-3`), not the RTX 5090:

- X output for the Dell is `HDMI-1-0` on an evdi slave provider with
  `PRIME Synchronization: supported: ?, ?` — no vblank sync, software
  cursor over USB → inherently jumpy, worse under load (box idles ~3).
- The kernel shows only ONE real enabled GPU connector: the ultrawide on
  the iGPU (`card1-HDMI-A-2`). That's why only the Dell jitters.
- The 5090's HDMI port (`DFP-0`) already reads the Dell's EDID — a direct
  HDMI cable 5090→Dell exists; the monitor is just on the dock input.
- Since 12:21 the dock's OTHER head (`card2-DVI-I-1`, EDID "CN45010DT8")
  flaps connected/EDID every ~20–30s, forcing X to re-probe all GPUs each
  time → periodic cursor freezes on top of the baseline jitter.

## Fix (physical)

1. Dell front panel: **switch input source to the HDMI input wired to the
   5090** (the one that shows DFP-0 in nvidia logs).
2. Reseat or unplug whatever is on the dock's DVI head (card2, the
   flapping one).
3. Optional: dock + external HDD share the ASM1074 USB hub — give the dock
   a root port if keeping DisplayLink use.

## Verification

After switching inputs, the Dell should move to an NVIDIA-provider output
with a real kernel CRTC:

```bash
for c in /sys/class/drm/card*-*/; do
  s=$(cat $c/status 2>/dev/null); e=$(cat $c/enabled 2>/dev/null)
  [ "$e" = "enabled" ] && echo "$(basename $c) $s/$e"
done
```

Should list the ultrawide AND the Dell (nvidia card, HDMI-A-*), and jitter
should be gone. Related: `docs/fix-boot-without-usb-hdd.md` (same dock/USB
hub neighborhood; GRUB fix there still needs its reboot test).
