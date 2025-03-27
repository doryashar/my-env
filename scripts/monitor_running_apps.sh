#!/bin/bash

MONITOR_INTERVAL=5  # Check every 5 seconds
LOCKDIR="/tmp"
SCRIPT_REGISTRY="/tmp/registered_scripts.list"

register_script() {
    local script_name="$1"
    grep -qxF "$script_name" "$SCRIPT_REGISTRY" 2>/dev/null || echo "$script_name" >> "$SCRIPT_REGISTRY"
}

remove_script() {
    local script_name="$1"
    sed -i "/^$script_name\$/d" "$SCRIPT_REGISTRY"
    echo "$script_name removed from registry."
}

list_scripts() {
    echo "Monitored scripts:"
    cat "$SCRIPT_REGISTRY" 2>/dev/null || echo "No scripts registered."
}

monitor_scripts() {
    while true; do
        while read -r script; do
            if ! pgrep -f "$script" &>/dev/null; then
                echo "Restarting $script..."
                nohup "$script" &>/dev/null &
            fi
        done < "$SCRIPT_REGISTRY"
        sleep "$MONITOR_INTERVAL"
    done
}

# Ensure the script is running once
source /path/to/ensure_single_instance.sh

# Start monitoring
monitor_scripts