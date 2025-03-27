#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Check for Wayland environment
if [ -n "$WAYLAND_DISPLAY" ]; then
    if command_exists hyprctl; then
        hyprctl activewindow | grep -Eo 'class: .*' | awk '{print $2}'
    elif command_exists swaymsg; then
        swaymsg -t get_tree | jq -r '.. | objects | select(.focused?) | .app_id // .name'
    else
        echo "Wayland detected, but no supported tools found."
    fi

# Check for X11 environment
elif [ -n "$DISPLAY" ]; then
    if command_exists xdotool; then
        win_id=$(xdotool getwindowfocus)
        xdotool getwindowclassname "$win_id"
    elif command_exists wmctrl; then
        win_id=$(xdotool getwindowfocus)
        wmctrl -lp | grep "$win_id" | awk '{print $NF}'
    else
        echo "X11 detected, but no supported tools found."
    fi
else
    echo "Neither X11 nor Wayland detected."
fi
