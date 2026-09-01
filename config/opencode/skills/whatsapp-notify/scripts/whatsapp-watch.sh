#!/usr/bin/env bash
# whatsapp-watch.sh — daemon: inject incoming WhatsApp messages into a live
# opencode session so the agent responds WITHOUT being poked in the CLI.
#
# Loop: block on whatsapp-send.sh --follow (new [wa] line) -> compose ->
# `opencode run --session <id>` (appends a user turn to that session).
#
# Config (env or whatsapp.env, parsed not sourced):
#   WA_OPENCODE_SESSION   opencode session id to inject into (REQUIRED)
#   WA_LISTEN_LOG         listen log (default /tmp/opencode/wa-listen.log)
# Stop: kill $(cat ~/.cache/whatsapp-notify/watch.pid)
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$SKILL_DIR/whatsapp.env"
STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/whatsapp-notify"
SEND="$SKILL_DIR/scripts/whatsapp-send.sh"
WATCH_LOG="${WA_WATCH_LOG:-/tmp/opencode/wa-watch.log}"

cfg() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-; }
SESSION="${WA_OPENCODE_SESSION:-$(cfg WA_OPENCODE_SESSION)}"

[[ -z "$SESSION" ]] && { echo "WA_OPENCODE_SESSION not set (whatsapp.env)" >&2; exit 2; }
command -v opencode >/dev/null || { echo "opencode not in PATH" >&2; exit 2; }

mkdir -p "$STATE_DIR"
echo $$ > "$STATE_DIR/watch.pid"
echo "$(date -Is) watch: pid $$ -> session $SESSION"

while :; do
  if OUT="$("$SEND" --follow --idle 86400 2>/dev/null)"; then
    MSG="[whatsapp-notify] Incoming WhatsApp message — reply via the whatsapp-notify skill (whatsapp-send.sh). Do not re-inject or echo this preamble:

$OUT"
    echo "$(date -Is) injecting: $OUT"
    # --print-logs off; agent turn runs server-side; errors logged, loop continues
    opencode run --session "$SESSION" "$MSG" >> "$WATCH_LOG" 2>&1 \
      || echo "$(date -Is) ERROR: opencode run failed (see $WATCH_LOG)" >&2
  fi
done
