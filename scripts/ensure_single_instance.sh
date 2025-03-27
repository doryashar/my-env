#!/bin/bash

LOCKDIR="/tmp"
LOCKFD=200

ensure_single_instance() {
    local script_name=$(basename "$0")
    local lockfile="$LOCKDIR/${script_name}.lock"
    
    if command -v flock &>/dev/null; then
        exec {LOCKFD}>"$lockfile" || exit 1
        flock -n "$LOCKFD" || { echo "$script_name is already running."; exit 1; }
    else
        if [ -f "$lockfile" ] && kill -0 "$(cat "$lockfile")" 2>/dev/null; then
            echo "$script_name is already running."
            exit 1
        fi
        echo $$ > "$lockfile"
        trap 'rm -f "$lockfile"' EXIT
    fi
}

# Call function when sourced
ensure_single_instance
