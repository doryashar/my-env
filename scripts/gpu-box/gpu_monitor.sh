#!/usr/bin/env bash
# Live GPU monitor for inference sessions — gpu-box
# Usage: gpu_monitor.sh [duration_seconds]  (default: 3600)
# Appends 1-sec samples (power, temp, clocks, util, vram) to ~/models/gpu-dmon.log
# so a Xid 79 moment has numbers attached. Safe to run alongside llama-swap.
D="${1:-3600}"
LOG="$HOME/models/gpu-dmon.log"
echo "=== monitor start $(date -Is) dur=${D}s ===" >> "$LOG"
timeout "$D" nvidia-smi dmon -s pum -d 1 -o TD >> "$LOG" 2>&1
echo "=== monitor end $(date -Is) ===" >> "$LOG"
