#!/usr/bin/env bash
# telegram-send.sh — Send messages and files via Telegram Bot API
# Usage:
#   telegram-send.sh "message text"
#   telegram-send.sh --file /path/to/doc.pdf
#   telegram-send.sh --photo /path/to/img.png
#   telegram-send.sh --document /path/to/file.pdf
#   telegram-send.sh --audio /path/to/song.mp3
#   telegram-send.sh --video /path/to/clip.mp4
#   telegram-send.sh --silent "text"      (default, explicit)
#   telegram-send.sh --loud "text"
set -euo pipefail

TYPE="text"
PAYLOAD=""
SILENT=1

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file|--document)
      TYPE="document"
      PAYLOAD="$2"
      shift 2
      ;;
    --photo)
      TYPE="photo"
      PAYLOAD="$2"
      shift 2
      ;;
    --audio)
      TYPE="audio"
      PAYLOAD="$2"
      shift 2
      ;;
    --video)
      TYPE="video"
      PAYLOAD="$2"
      shift 2
      ;;
    --silent)
      SILENT=1
      if [[ -n "${2:-}" && "$2" != --* ]]; then
        PAYLOAD="$2"
        shift
      fi
      shift
      ;;
    --loud)
      SILENT=0
      if [[ -n "${2:-}" && "$2" != --* ]]; then
        PAYLOAD="$2"
        shift
      fi
      shift
      ;;
    *)
      if [[ -z "$PAYLOAD" ]]; then
        PAYLOAD="$1"
      fi
      shift
      ;;
  esac
done

# Validate env
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  echo "ERROR: TELEGRAM_BOT_TOKEN not set" >&2
  exit 1
fi
if [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "ERROR: TELEGRAM_CHAT_ID not set" >&2
  exit 1
fi

API="https://api.telegram.org/${TELEGRAM_BOT_TOKEN}"

# Text message
if [[ "$TYPE" == "text" ]]; then
  response=$(curl --silent --show-error -X POST \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg chat_id "$TELEGRAM_CHAT_ID" --arg text "$PAYLOAD" --argjson silent "$SILENT" \
      '{chat_id: $chat_id, text: $text, disable_notification: $silent}')" \
    "$API/sendMessage")
  if echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
    exit 0
  else
    echo "ERROR: $response" >&2
    exit 1
  fi
fi

# File types - send via multipart
if [[ -z "$PAYLOAD" ]]; then
  echo "ERROR: file path required for $TYPE" >&2
  exit 1
fi
if [[ ! -f "$PAYLOAD" ]]; then
  echo "ERROR: file not found: $PAYLOAD" >&2
  exit 1
fi

FILENAME=$(basename "$PAYLOAD")

if [[ "$TYPE" == "document" ]]; then
  response=$(curl --silent --show-error -X POST \
    -F "chat_id=$TELEGRAM_CHAT_ID" \
    -F "document=@$PAYLOAD;filename=$FILENAME" \
    -F "disable_notification=$SILENT" \
    "$API/sendDocument")
else
  # photo, audio, video
  response=$(curl --silent --show-error -X POST \
    -F "chat_id=$TELEGRAM_CHAT_ID" \
    -F "${TYPE}=@$PAYLOAD;filename=$FILENAME" \
    -F "disable_notification=$SILENT" \
    "$API/send${TYPE}")
fi

if echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
  exit 0
else
  echo "ERROR: $response" >&2
  exit 1
fi