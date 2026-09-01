#!/usr/bin/env bash
# whatsapp-send.sh — Send/receive WhatsApp via Evolution API.
# Usage:
#   whatsapp-send.sh "message text"
#   whatsapp-send.sh --to 972548826569 "message text"
#   whatsapp-send.sh --file /path/to/doc.pdf ["caption"]
#   whatsapp-send.sh --photo /path/to/img.png ["caption"]
#   whatsapp-send.sh --list                        (list instances + status)
#   whatsapp-send.sh --wait ["greeting"] [--timeout SECS]   block until a message arrives from the user
#   whatsapp-send.sh --listen [--interval SECS]    foreground loop printing new incoming messages
#   whatsapp-send.sh --follow [--idle SECS]        block until the listen log gets a new line (0=got one, 3=idle)
# Exit codes: 0 ok/received; 1 API error; 2 config error; 3 wait timed out.
#
# Receive notes:
# - Incoming messages may arrive under an @lid JID, NOT the phone-number JID —
#   never filter by phone JID. We accept every non-fromMe message.
# - The server's fromMe filter is broken (falsy check) — filtered client-side.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$SKILL_DIR/whatsapp.env"
STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/whatsapp-notify"
STATE_FILE="$STATE_DIR/state.json"

cfg() { # cfg KEY -> value from env file, no shell evaluation
  grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-
}

API_URL="${EVOLUTION_API_URL:-$(cfg EVOLUTION_API_URL)}"
API_KEY="${EVOLUTION_API_KEY:-$(cfg EVOLUTION_API_KEY)}"
INSTANCE="${EVOLUTION_INSTANCE:-$(cfg EVOLUTION_INSTANCE)}"
RECIPIENT="${WA_DEFAULT_RECIPIENT:-$(cfg WA_DEFAULT_RECIPIENT)}"

MODE="send"; TYPE="text"; PAYLOAD=""; CAPTION=""; FILE_DONE=""
TIMEOUT=300; INTERVAL=3; IDLE=180; FOLLOW_LOG="${WA_LISTEN_LOG:-/tmp/opencode/wa-listen.log}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)       RECIPIENT="$2"; shift 2 ;;
    --instance) INSTANCE="$2"; shift 2 ;;
    --file)     TYPE="document"; PAYLOAD="$2"; shift 2 ;;
    --photo)    TYPE="image"; PAYLOAD="$2"; shift 2 ;;
    --audio)    TYPE="audio"; PAYLOAD="$2"; shift 2 ;;
    --video)    TYPE="video"; PAYLOAD="$2"; shift 2 ;;
    --list)     MODE="list"; shift ;;
    --wait)     MODE="wait"; shift ;;
    --listen)   MODE="listen"; shift ;;
    --follow)   MODE="follow"; shift ;;
    --timeout)  TIMEOUT="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --idle)     IDLE="$2"; shift 2 ;;
    --log)      FOLLOW_LOG="$2"; shift 2 ;;
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

if [[ "$MODE" == "list" ]]; then
  api "$API_URL/instance/fetchInstances" | jq -r '.[] | "\(.name)\t\(.connectionStatus)\t\(.profileName // "-")\t\(.ownerJid // "-")"'
  exit 0
fi

# ---------- receive machinery (wait / listen) ----------
# POST /chat/findMessages — response: .messages.records[]
# Quirks: messageTimestamp filter only applies when BOTH gte and lte present;
# fromMe server filter is broken (falsy JS check) -> filter client-side;
# incoming user messages arrive under @lid JIDs -> never filter by phone JID.
fetch_records() { # fetch_records FROM_EPOCH -> records JSON array (sorted asc)
  local gte lte
  gte="$(date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ)"
  lte="$(date -u -d "@$(( $(date +%s) + 60 ))" +%Y-%m-%dT%H:%M:%SZ)"
  local body
  body="$(jq -n --arg gte "$gte" --arg lte "$lte" \
    '{where: {messageTimestamp: {gte: $gte, lte: $lte}}, offset: 100, page: 1}')"
  api -X POST "$API_URL/chat/findMessages/$INSTANCE" -d "$body" \
    | jq '[.messages.records[] | select(.key.fromMe == false)] | sort_by(.messageTimestamp)'
}

state_read() { # -> sets LAST_TS (int), SEEN (comma list)
  LAST_TS=0; SEEN=""
  if [[ -f "$STATE_FILE" ]]; then
    LAST_TS="$(jq -r '.last_ts // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
    SEEN="$(jq -r '.seen // [] | join(",")' "$STATE_FILE" 2>/dev/null || echo "")"
  fi
  return 0
}

state_write() { # state_write LAST_TS EPOCH [ID...] (append/replace seen, keep last 50)
  local last_ts="$1"; shift
  local seen_json
  seen_json="$(printf '%s\n' "$@" | jq -R . | jq -s 'map(select(length > 0))')"
  local tmp; tmp="$(mktemp "$STATE_FILE.XXXXXX")"
  jq -n --argjson ts "$last_ts" --argjson seen "$seen_json" '{last_ts: $ts, seen: $seen}' > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

seen_has() { local IFS=','; [[ ",$SEEN," == *",$1,"* ]]; }

fmt_msg() { # fmt_msg RECORD -> one human line (local time via date(1))
  local line ts jid pn mtype cap
  line="$(jq -r '
    (.messageTimestamp | tonumber) as $ts
    | (.message.conversation
       // .message.extendedTextMessage.text
       // .message.imageMessage.caption
       // .message.documentMessage.caption
       // .message.videoMessage.caption
       // "") as $cap
    | "\($ts)\t\(.key.remoteJid // "?")\t\(.pushName // "-")\t\(.messageType)\t\($cap)"' <<< "$1")"
  IFS=$'\t' read -r ts jid pn mtype cap <<< "$line"
  local text="$cap"
  [[ -z "$text" && "$mtype" != "conversation" && "$mtype" != "extendedTextMessage" ]] && text="[$mtype]"
  echo "[wa] $(date -d "@$ts" +%Y-%m-%dT%H:%M:%S) from $jid ($pn): $text"
}

if [[ "$MODE" == "wait" || "$MODE" == "listen" ]]; then
  mkdir -p "$STATE_DIR"
fi

if [[ "$MODE" == "wait" ]]; then
  if [[ -n "$PAYLOAD" ]]; then
    # send optional greeting first, then wait
    BODY="$(jq -n --arg number "$RECIPIENT" --arg text "$PAYLOAD" '{number: $number, text: $text}')"
    api -X POST "$API_URL/message/sendText/$INSTANCE" -d "$BODY" >/dev/null \
      || { echo "ERROR: greeting send failed" >&2; exit 1; }
  fi
  START="$(date +%s)"
  DEADLINE=$(( START + TIMEOUT ))
  state_read
  echo "waiting for a message (timeout ${TIMEOUT}s)..."
  while :; do
    NOW="$(date +%s)"
    [[ "$NOW" -ge "$DEADLINE" ]] && { echo "timeout: no message in ${TIMEOUT}s" >&2; exit 3; }
    RECORDS="$(fetch_records "$(( NOW - 120 ))")" || { sleep "$INTERVAL"; continue; }
    MATCH="$(jq -c '[.[] | select(.messageTimestamp >= '"$START"')] | first // empty' <<< "$RECORDS")"
    if [[ -n "$MATCH" ]] && ! seen_has "$(jq -r '.key.id' <<< "$MATCH")"; then
      fmt_msg "$MATCH"
      state_write "$NOW" "$(jq -r '.key.id' <<< "$MATCH")"
      exit 0
    fi
    sleep "$INTERVAL"
  done
fi

if [[ "$MODE" == "listen" ]]; then
  # start from "now" (no history replay), but never behind persisted state
  state_read
  NOW="$(date +%s)"
  WATERMARK="$NOW"
  [[ "$LAST_TS" -gt 0 && "$LAST_TS" -lt "$WATERMARK" ]] && WATERMARK="$LAST_TS"
  echo $$ > "$STATE_DIR/listen.pid"
  echo "listening (interval ${INTERVAL}s, pid $$); watermark=$WATERMARK"
  while :; do
    RECORDS="$(fetch_records "$(( WATERMARK - 1 ))")" || { sleep "$INTERVAL"; continue; }
    while IFS= read -r rec; do
      [[ -z "$rec" ]] && continue
      MID="$(jq -r '.key.id' <<< "$rec")"
      TS="$(jq -r '.messageTimestamp' <<< "$rec")"
      seen_has "$MID" && continue
      fmt_msg "$rec"
      SEEN="$SEEN${SEEN:+,}$MID"
      [[ "$TS" -gt "$WATERMARK" ]] && WATERMARK="$TS"
    done < <(jq -c '.[]' <<< "$RECORDS")
    # persist (keep seen list bounded)
    state_write "$WATERMARK" ${SEEN:+$(echo "$SEEN" | tr ',' '\n' | tail -50)}
    sleep "$INTERVAL"
  done
fi

if [[ "$MODE" == "follow" ]]; then
  # Block until new [wa] line(s) appear in the listen log (written by --listen).
  # Prints them and exits 0; exit 3 after IDLE seconds of silence.
  size() { wc -c < "$FOLLOW_LOG" 2>/dev/null || echo 0; }
  [[ -f "$FOLLOW_LOG" ]] || { echo "no listen log at $FOLLOW_LOG — start --listen first" >&2; exit 2; }
  OFF="$(size)"
  LAST="$(date +%s)"
  echo "following $FOLLOW_LOG (idle ${IDLE}s)..."
  while :; do
    SIZE="$(size)"
    if [[ "$SIZE" -gt "$OFF" ]]; then
      CHUNK_BYTES=$(( SIZE - OFF ))
      COMPLETE_LN="$(tail -c +"$(( OFF + 1 ))" "$FOLLOW_LOG" | wc -l)"
      if [[ "$COMPLETE_LN" -ge 1 ]]; then
        LINES="$(tail -c +"$(( OFF + 1 ))" "$FOLLOW_LOG" | head -n "$COMPLETE_LN")"
        OFF=$(( OFF + $(printf '%s' "$LINES" | wc -c) + 1 ))  # +1: newline stripped by $()
        # only real listener lines: "[wa] YYYY-MM-DD..." (log may contain test noise)
        MATCHED="$(grep '^\[wa\] [0-9]\{4\}-[0-9]\{2\}-' <<< "$LINES" || true)"
        if [[ -n "$MATCHED" ]]; then
          echo "$MATCHED"
          exit 0
        fi
      fi
    fi
    NOW="$(date +%s)"
    [[ $(( NOW - LAST )) -ge "$IDLE" ]] && { echo "idle: nothing new in ${IDLE}s" >&2; exit 3; }
    sleep 0.5
  done
fi

# ---------- send ----------
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
