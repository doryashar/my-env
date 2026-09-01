#!/usr/bin/env bash
# whatsapp-send.sh — Send messages/files to the user via Evolution API (WhatsApp).
# Usage:
#   whatsapp-send.sh "message text"
#   whatsapp-send.sh --to 972548826569 "message text"
#   whatsapp-send.sh --file /path/to/doc.pdf ["caption"]
#   whatsapp-send.sh --photo /path/to/img.png ["caption"]
#   whatsapp-send.sh --list            (list instances + connection status)
# Exit codes: 0 sent; 1 API error; 2 config error.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$SKILL_DIR/whatsapp.env"

cfg() { # cfg KEY -> value from env file, no shell evaluation
  grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-
}

API_URL="${EVOLUTION_API_URL:-$(cfg EVOLUTION_API_URL)}"
API_KEY="${EVOLUTION_API_KEY:-$(cfg EVOLUTION_API_KEY)}"
INSTANCE="${EVOLUTION_INSTANCE:-$(cfg EVOLUTION_INSTANCE)}"
RECIPIENT="${WA_DEFAULT_RECIPIENT:-$(cfg WA_DEFAULT_RECIPIENT)}"

TYPE="text"; PAYLOAD=""; CAPTION=""; FILE_DONE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)       RECIPIENT="$2"; shift 2 ;;
    --instance) INSTANCE="$2"; shift 2 ;;
    --file)     TYPE="document"; PAYLOAD="$2"; shift 2 ;;
    --photo)    TYPE="image"; PAYLOAD="$2"; shift 2 ;;
    --audio)    TYPE="audio"; PAYLOAD="$2"; shift 2 ;;
    --video)    TYPE="video"; PAYLOAD="$2"; shift 2 ;;
    --list)     MODE="list"; shift ;;
    *)
                if [[ "$TYPE" != "text" ]]; then
                  # first positional after a media flag = caption, rest ignored
                  [[ -z "$CAPTION" && -z "$FILE_DONE" ]] && CAPTION="$1"
                  FILE_DONE=1
                elif [[ -z "$PAYLOAD" ]]; then
                  PAYLOAD="$1"
                fi
                shift ;;
  esac
done

api() { curl --silent --show-error --max-time 30 -H "apikey: $API_KEY" -H "Content-Type: application/json" "$@"; }

# Digits only (strip +, spaces, dashes)
RECIPIENT="$(echo "$RECIPIENT" | tr -d ' +-.()' )"

if [[ -z "$API_URL" || -z "$API_KEY" ]]; then
  echo "ERROR: missing EVOLUTION_API_URL / EVOLUTION_API_KEY (checked env + $ENV_FILE)" >&2
  exit 2
fi

if [[ "${MODE:-}" == "list" ]]; then
  api "$API_URL/instance/fetchInstances" | jq -r '.[] | "\(.name)\t\(.connectionStatus)\t\(.profileName // "-")\t\(.ownerJid // "-")"'
  exit 0
fi

if [[ -z "$RECIPIENT" ]]; then
  echo "ERROR: no recipient (WA_DEFAULT_RECIPIENT or --to)" >&2
  exit 2
fi

if [[ "$TYPE" == "text" ]]; then
  [[ -z "$PAYLOAD" ]] && { echo "ERROR: empty message" >&2; exit 2; }
  BODY="$(jq -n --arg number "$RECIPIENT" --arg text "$PAYLOAD" '{number: $number, text: $text}')"
  response=$(api -X POST "$API_URL/message/sendText/$INSTANCE" -d "$BODY")
else
  [[ -f "$PAYLOAD" ]] || { echo "ERROR: file not found: $PAYLOAD" >&2; exit 2; }
  MIME=$(file --brief --mime-type "$PAYLOAD")
  # Evolution expects PLAIN base64 (no data: URI prefix) or a URL
  MEDIA="$(base64 -w0 "$PAYLOAD")"
  FILENAME=$(basename "$PAYLOAD")
  BODY="$(jq -n --arg number "$RECIPIENT" --arg mediatype "$TYPE" --arg media "$MEDIA" \
              --arg fileName "$FILENAME" --arg caption "$CAPTION" \
              '{number: $number, mediatype: $mediatype, media: $media, fileName: $fileName, caption: $caption}')"
  response=$(api -X POST "$API_URL/message/sendMedia/$INSTANCE" -d "$BODY")
fi

if echo "$response" | jq -e '.key.id' >/dev/null 2>&1; then
  echo "sent: $(echo "$response" | jq -r '.key.id') -> $RECIPIENT via $INSTANCE (status $(echo "$response" | jq -r '.status'))"
  exit 0
else
  echo "ERROR: $response" >&2
  exit 1
fi
