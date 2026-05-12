#!/bin/bash
set -e

# Check for Wayland environment
if [ -n "$WAYLAND_DISPLAY" ]; then
    if command -v hyprctl &>/dev/null; then
        hyprctl activewindow | grep -Eo 'class: .*' | awk '{print $2}'
    elif command -v swaymsg &>/dev/null; then
        swaymsg -t get_tree | jq -r '.. | objects | select(.focused?) | .app_id // .name'
    else
        echo "Wayland detected, but no supported tools found."
    fi

# Check for X11 environment
elif [ -n "$DISPLAY" ]; then
    if command -v xdotool &>/dev/null; then
        win_id=$(xdotool getwindowfocus)
        xdotool getwindowclassname "$win_id"
    elif command -v wmctrl &>/dev/null; then
        win_id=$(xdotool getwindowfocus)
        wmctrl -lp | grep "$win_id" | awk '{print $NF}'
    else
        echo "X11 detected, but no supported tools found."
    fi
else
    echo "Neither X11 nor Wayland detected."
fi
