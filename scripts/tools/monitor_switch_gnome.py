#!/usr/bin/env python3
"""
GNOME monitor switching tool using DBus API
"""

import sys
import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib


def _monitor_resolution(monitor):
    """Return (width, height) from a monitor's representative mode, else None."""
    modes = monitor[1]
    if not modes:
        return None
    mode = modes[0]
    try:
        return (int(mode[1]), int(mode[2]))
    except (IndexError, ValueError, TypeError):
        return None


def _match_by_edid(monitors, vid, claimed):
    """First unclaimed monitor whose EDID vendor startswith vid.

    Returns (connector, width) or (None, None).
    """
    vid_u = vid.upper()
    for monitor in monitors:
        connector = monitor[0][0]
        if connector in claimed:
            continue
        vendor = monitor[0][1] or ""
        if vendor.upper().startswith(vid_u):
            res = _monitor_resolution(monitor)
            return connector, (res[0] if res else 1920)
    return None, None


def _match_by_resolution(monitors, expected_res, claimed):
    """First unclaimed monitor whose mode resolution equals expected_res.

    expected_res is "WxH" (e.g. "5120x1440"). Returns (connector, width)
    or (None, None).
    """
    try:
        ew_s, eh_s = str(expected_res).lower().split("x", 1)
        expected = (int(ew_s), int(eh_s))
    except (ValueError, AttributeError):
        return None, None
    for monitor in monitors:
        connector = monitor[0][0]
        if connector in claimed:
            continue
        res = _monitor_resolution(monitor)
        if res is not None and res == expected:
            return connector, res[0]
    return None, None


def resolve_vendors(monitors, vendor_specs):
    """Resolve vendor IDs to (vid, connector, width).

    EDID vendor match is primary; expected_resolution is a fallback used only
    when no EDID match is found (e.g. EDID reads as "unknown"). Each monitor
    is claimed at most once.

    Args:
        monitors: parsed monitor list from GetCurrentState.unpack().
        vendor_specs: list of (vid, expected_resolution_or_None), where
            expected_resolution is "WxH" or None.

    Returns:
        list of (vid, connector, width) in declaration order.
    """
    claimed = set()
    results = []
    for vid, expected_res in vendor_specs:
        connector, width = _match_by_edid(monitors, vid, claimed)
        if connector is None and expected_res:
            connector, width = _match_by_resolution(
                monitors, expected_res, claimed
            )
        if connector is not None:
            claimed.add(connector)
            results.append((vid, connector, width))
    return results


def parse_resolve_args(tokens):
    """Parse resolve CLI tokens into (vid, expected_resolution_or_None).

    Accepts both 'VID' (EDID-only) and 'VID=WxH' (with resolution hint).
    An empty resolution ('VID=') is treated as None (EDID-only).
    """
    specs = []
    for token in tokens:
        if "=" in token:
            vid, res = token.split("=", 1)
            res = res.strip()
            specs.append((vid, res or None))
        else:
            specs.append((token, None))
    return specs


class MonitorSwitcher:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.proxy = Gio.DBusProxy.new_sync(
            self.bus,
            Gio.DBusProxyFlags.NONE,
            None,
            "org.gnome.Mutter.DisplayConfig",
            "/org/gnome/Mutter/DisplayConfig",
            "org.gnome.Mutter.DisplayConfig",
            None,
        )

    def get_current_state(self):
        """Get current monitor configuration"""
        result = self.proxy.call_sync(
            "GetCurrentState", None, Gio.DBusCallFlags.NONE, -1, None
        )
        return result.unpack()

    def apply_config(self, serial, method, logical_monitors, properties):
        """Apply monitor configuration"""
        try:
            # Format: (serial, method, logical_monitors_array, properties)
            # logical_monitors_array: a(iiduba(ssa{sv}))
            # Each logical monitor: (x, y, scale, transform, primary, [(connector, mode_id, props)])
            # Each monitor tuple: (connector_name, mode_id, properties)

            # Use method 1 (temporary) instead of 2 (persistent) to avoid confirmation dialog
            # We'll make it persistent by not reverting it
            self.proxy.call_sync(
                "ApplyMonitorsConfig",
                GLib.Variant(
                    "(uua(iiduba(ssa{sv}))a{sv})",
                    (serial, 1, logical_monitors, properties),
                ),
                Gio.DBusCallFlags.NONE,
                -1,
                None,
            )
            return True
        except Exception as e:
            print(f"Error applying config: {e}")
            return False

    def list_monitors(self):
        """List all monitors"""
        serial, monitors, logical_monitors, properties = self.get_current_state()

        print("Available monitors:")
        for i, monitor in enumerate(monitors):
            connector = monitor[0][0]
            vendor = monitor[0][1]
            product = monitor[0][2]
            serial_num = monitor[0][3]
            modes = monitor[1]
            print(f"\n  Monitor {i}: {connector}")
            print(f"    Vendor: {vendor}, Product: {product}, Serial: {serial_num}")
            if modes:
                current_mode = modes[0]
                print(
                    f"    Current mode: {current_mode[1]}x{current_mode[2]} @ {current_mode[3]:.2f}Hz"
                )

        print("\nActive logical monitors:")
        for i, lm in enumerate(logical_monitors):
            x, y, scale, transform, primary, monitors_list = (
                lm[0],
                lm[1],
                lm[2],
                lm[3],
                lm[4],
                lm[5],
            )
            print(
                f"  Logical monitor {i}: position ({x}, {y}), scale {scale}, primary: {primary}"
            )
            for mon in monitors_list:
                print(f"    - {mon[0]} using mode {mon[1][1]}x{mon[1][2]}")

    def get_active_monitors(self):
        """Get list of active monitor connectors (space-separated for shell parsing)"""
        serial, monitors, logical_monitors, properties = self.get_current_state()
        active_connectors = []
        for lm in logical_monitors:
            for mon in lm[5]:  # monitors_list is at index 5
                active_connectors.append(mon[0])  # connector name
        print(" ".join(active_connectors))

    def get_available_monitors(self):
        """Get list of all available monitor connectors (space-separated for shell parsing)"""
        serial, monitors, logical_monitors, properties = self.get_current_state()
        connectors = [monitor[0][0] for monitor in monitors]
        print(" ".join(connectors))

    def resolve_monitors(self, vendor_specs):
        """Resolve vendor specs to connector names with widths.

        vendor_specs: list of (vid, expected_resolution_or_None). Prints
        'vid connector width' per resolved vendor. EDID vendor match is
        primary; expected_resolution is a fallback when EDID is unknown.
        """
        serial, monitors, logical_monitors, properties = self.get_current_state()
        for vid, connector, width in resolve_vendors(monitors, vendor_specs):
            print(f"{vid} {connector} {width}")

    def enable_single_monitor(self, target_connector):
        """Enable only the specified monitor and disable others"""
        serial, monitors, logical_monitors, properties = self.get_current_state()

        # Find the target monitor
        target_monitor = None
        target_modes = None

        for monitor in monitors:
            connector = monitor[0][0]
            if connector == target_connector:
                target_monitor = monitor[0]
                target_modes = monitor[1]
                break

        if not target_monitor:
            print(f"Error: Monitor {target_connector} not found")
            return False

        if not target_modes:
            print(f"Error: No modes available for {target_connector}")
            return False

        # Get the mode ID
        preferred_mode = target_modes[0]
        mode_id = preferred_mode[0]

        # Create new logical monitor configuration with only the target monitor
        # Format: (x, y, scale, transform, primary, [(connector, mode_id, properties)])
        # NO extra properties dict at the end!
        new_logical_monitors = [
            (
                0,  # x position
                0,  # y position
                1.0,  # scale
                0,  # transform (0 = normal)
                True,  # primary
                [
                    (target_connector, mode_id, {})
                ],  # list of (connector_name, mode_id, properties) tuples
            )
        ]

        # Apply configuration (method 1 = temporary, no confirmation dialog)
        return self.apply_config(serial, 1, new_logical_monitors, {})

    def enable_multiple_monitors(
        self, target_connectors, primary_connector=None, positions=None
    ):
        """Enable multiple monitors with explicit positioning

        Args:
            target_connectors: List of monitor connectors to enable
            primary_connector: Which connector should be primary (default: first one)
            positions: Dict mapping connector names to x positions (optional)
        """
        serial, monitors, logical_monitors, properties = self.get_current_state()

        # If no primary specified, use the first connector
        if primary_connector is None:
            primary_connector = target_connectors[0]

        # Find all target monitors
        monitor_configs = []
        for target_connector in target_connectors:
            found = False
            for monitor in monitors:
                connector = monitor[0][0]
                if connector == target_connector:
                    mode_id = monitor[1][0][0]  # Get preferred mode
                    monitor_configs.append((connector, mode_id))
                    found = True
                    break
            if not found:
                print(f"Error: Monitor {target_connector} not found")
                return False

        if not monitor_configs:
            print("Error: No monitors found")
            return False

        # Create logical monitors with specified positions
        new_logical_monitors = []

        if positions:
            # Use explicit positions
            for connector, mode_id in monitor_configs:
                x_pos = positions.get(connector, 0)
                new_logical_monitors.append(
                    (
                        x_pos,  # x position (explicit)
                        0,  # y position
                        1.0,  # scale
                        0,  # transform
                        connector == primary_connector,  # is this the primary?
                        [(connector, mode_id, {})],
                    )
                )
        else:
            # Position side by side
            x_offset = 0
            for i, (connector, mode_id) in enumerate(monitor_configs):
                # Get the width of this monitor from the mode string
                width = 1920  # Default width
                try:
                    if "x" in mode_id:
                        width = int(mode_id.split("x")[0])
                except:
                    pass

                new_logical_monitors.append(
                    (
                        x_offset,  # x position
                        0,  # y position
                        1.0,  # scale
                        0,  # transform
                        connector == primary_connector,  # is this the primary?
                        [(connector, mode_id, {})],
                    )
                )
                x_offset += width

        # Apply configuration (method 1 = temporary, no confirmation dialog)
        return self.apply_config(serial, 1, new_logical_monitors, {})


def main():
    if len(sys.argv) < 2:
        print(
            "Usage: monitor-switch-gnome.py <list|get-active|enable CONNECTOR|profile [--primary CONNECTOR] CONNECTOR1 CONNECTOR2...>"
        )
        sys.exit(1)

    switcher = MonitorSwitcher()

    command = sys.argv[1]

    if command == "list":
        switcher.list_monitors()
    elif command == "get-active":
        switcher.get_active_monitors()
    elif command == "get-available":
        switcher.get_available_monitors()
    elif command == "enable" and len(sys.argv) == 3:
        connector = sys.argv[2]
        if switcher.enable_single_monitor(connector):
            print(f"Successfully enabled {connector}")
        else:
            print(f"Failed to enable {connector}")
            sys.exit(1)
    elif command == "resolve" and len(sys.argv) >= 3:
        switcher.resolve_monitors(parse_resolve_args(sys.argv[2:]))
    elif command == "profile" and len(sys.argv) >= 3:
        # Parse arguments for primary flag and positions
        primary_connector = None
        positions = {}
        connectors = []

        i = 2
        while i < len(sys.argv):
            if sys.argv[i] == "--primary" and i + 1 < len(sys.argv):
                primary_connector = sys.argv[i + 1]
                i += 2
            elif sys.argv[i] == "--pos" and i + 2 < len(sys.argv):
                # --pos CONNECTOR X_POSITION
                connector = sys.argv[i + 1]
                x_pos = int(sys.argv[i + 2])
                positions[connector] = x_pos
                i += 3
            else:
                connectors.append(sys.argv[i])
                i += 1

        if not connectors:
            print("Error: No monitors specified")
            sys.exit(1)

        pos_dict = positions if positions else None
        if switcher.enable_multiple_monitors(connectors, primary_connector, pos_dict):
            primary_info = (
                f" (primary: {primary_connector})" if primary_connector else ""
            )
            print(
                f"Successfully enabled profile: {', '.join(connectors)}{primary_info}"
            )
        else:
            print(f"Failed to enable profile")
            sys.exit(1)
    else:
        print("Invalid command")
        print(
            "Usage: monitor-switch-gnome.py <list|enable CONNECTOR|profile [--primary CONNECTOR] CONNECTOR1 CONNECTOR2...>"
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
