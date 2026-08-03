#!/usr/bin/env python3
"""Unit tests for monitor_switch_gnome resolver (no DBus/GNOME required)."""
import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "scripts", "tools")
)

from monitor_switch_gnome import resolve_vendors  # noqa: E402


def _mon(connector, vendor, w, h):
    """Build a monitor tuple shaped like GetCurrentState.unpack() entries:
    monitor[0] = (connector, vendor, product, serial); monitor[1] = modes
    where modes[0] = (mode_id, width, height, refresh)."""
    return (
        (connector, vendor, "product", "serial"),
        [("mode-id", w, h, 60.0)],
        {},
    )


def test_resolution_hint_fallback_when_edid_unknown():
    monitors = [
        _mon("DVI-I-2-1", "HWP", 1920, 1200),
        _mon("DVI-I-3-2", "DEL", 1920, 1200),
        _mon("HDMI-2", "unknown", 5120, 1440),
    ]
    specs = [("HWP", None), ("DEL", None), ("LEN", "5120x1440")]
    assert resolve_vendors(monitors, specs) == [
        ("HWP", "DVI-I-2-1", 1920),
        ("DEL", "DVI-I-3-2", 1920),
        ("LEN", "HDMI-2", 5120),
    ]


def test_edid_match_still_works():
    monitors = [_mon("DP-1", "HWP", 1920, 1200)]
    assert resolve_vendors(monitors, [("HWP", None)]) == [("HWP", "DP-1", 1920)]


def test_no_match_when_resolution_absent():
    monitors = [_mon("DP-1", "DEL", 1920, 1200)]
    assert resolve_vendors(monitors, [("LEN", "5120x1440")]) == []


def test_resolution_hint_cannot_steal_edid_claimed_monitor():
    monitors = [_mon("DP-1", "HWP", 5120, 1440)]
    specs = [("HWP", "5120x1440"), ("LEN", "5120x1440")]
    result = resolve_vendors(monitors, specs)
    assert ("HWP", "DP-1", 5120) in result
    assert not any(vid == "LEN" for vid, _, _ in result)


def test_width_defaults_when_no_modes():
    monitors = [(("DP-1", "HWP", "p", "s"), [], {})]
    assert resolve_vendors(monitors, [("HWP", None)]) == [("HWP", "DP-1", 1920)]
