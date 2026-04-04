#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../functions/pingme"

if [[ -z "${TELEGRAM_CHAT_ID:-}" || -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  SECRETS_FILE="${ENV_DIR:-$HOME/env}/tmp/private/secrets"
  if [[ -f "$SECRETS_FILE" ]]; then
    source "$SECRETS_FILE"
  else
    echo "Error: TELEGRAM_CHAT_ID and TELEGRAM_BOT_TOKEN must be set" >&2
    exit 1
  fi
fi

OREF_URL="https://www.oref.org.il/warningMessages/alert/Alerts.json"
POLL_INTERVAL="${OREF_POLL_INTERVAL:-0.1}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/oref_alerts"
SEEN_IDS_FILE="$STATE_DIR/seen_ids"
MAX_AREAS_DISPLAY=50
DEBUG="${OREF_DEBUG:-0}"
LOG_FILE="$STATE_DIR/debug.log"

mkdir -p "$STATE_DIR"
if [[ "$DEBUG" == "1" ]]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') - oref_alert_monitor started (pid=$$) ==="
fi
declare -A SEEN_IDS
if [[ -f "$SEEN_IDS_FILE" ]]; then
  while IFS='=' read -r k _; do
    [[ -n "$k" ]] && SEEN_IDS["$k"]=1
  done < "$SEEN_IDS_FILE"
fi

save_seen_ids() {
  : > "$SEEN_IDS_FILE"
  for k in "${!SEEN_IDS[@]}"; do
    echo "$k=1" >> "$SEEN_IDS_FILE"
  done
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

debug() {
  if [[ "$DEBUG" == "1" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*" >> "$LOG_FILE"
  fi
}

send_alert() {
  local title="$1"
  local desc="$2"
  local areas="$3"

  local msg="🚨 ${title}"
  if [[ -n "$areas" ]]; then
    msg+=$'\n\n'"${areas}"
  fi
  if [[ -n "$desc" ]]; then
    msg+=$'\n\n'"${desc}"
  fi

  pingme "$msg"
}

while true; do
  raw=$(curl -s --max-time 10 \
    -H "User-Agent: Mozilla/5.0" \
    -H "Referer: https://www.oref.org.il/" \
    "$OREF_URL" 2>/dev/null) || {
    sleep "$POLL_INTERVAL"
    continue
  }

  raw=$(echo "$raw" | tr -d '\0')

  #debug "Raw response: $raw"

  stripped=$(echo "$raw" | sed '1s/^\xef\xbb\xbf//' | tr -d '[:space:]')

  if [[ -z "$stripped" ]]; then
    sleep "$POLL_INTERVAL"
    continue
  fi

  clean=$(echo "$raw" | sed '1s/^\xef\xbb\xbf//')

  if ! alert_id=$(echo "$clean" | jq -r '.id' 2>/dev/null) || [[ "$alert_id" == "null" ]] || [[ -z "$alert_id" ]]; then
    sleep "$POLL_INTERVAL"
    continue
  fi

  if [[ -z "${SEEN_IDS[$alert_id]:-}" ]]; then
    SEEN_IDS["$alert_id"]=1
    save_seen_ids

    title=$(echo "$clean" | jq -r '.title // empty')
    desc=$(echo "$clean" | jq -r '.desc // empty')

    area_count=$(echo "$clean" | jq '.data | length')
    if [[ "$area_count" -gt "$MAX_AREAS_DISPLAY" ]]; then
      areas=$(echo "$clean" | jq -r ".data[:$MAX_AREAS_DISPLAY] | join(\", \")")
      areas+=" ... (+$((area_count - MAX_AREAS_DISPLAY)) more)"
    else
      areas=$(echo "$clean" | jq -r '.data | join(", ")')
    fi

    log "New alert: $title (id=$alert_id, areas=$area_count)"
    debug "$clean"

    if [[ -n "${MARK:-}" ]]; then
      matched=$(echo "$clean" | jq -r '.data[]' | grep -E "$MARK" || true)
      if [[ -z "$matched" ]]; then
        debug "No match for MARK='$MARK', skipping notification"
        sleep "$POLL_INTERVAL"
        continue
      fi
    fi

    send_alert "$title" "$desc" "$areas"
  fi

  sleep "$POLL_INTERVAL"
done
