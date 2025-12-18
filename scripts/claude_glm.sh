#!/usr/bin/env bash
# Alias script to run new_claude.sh with --glm flag
exec "$(dirname "$0")/new_claude.sh" --glm "$@"