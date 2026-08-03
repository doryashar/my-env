#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pytest "$SCRIPT_DIR/test_monitor_switch_gnome.py" -q
