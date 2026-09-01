#!/usr/bin/env bash
# whatsapp-health.sh — independent validation of every stage of the WhatsApp chain.
# Stages: S1 Evolution API+instance | S2 listener (pid/fd/loop) | S3 watch daemon
#         (+follow child) | S4 inbound freshness (store age, ssh docker logs)
# Options: --probe (also run the destructive-but-safe local self-test: inject a
#          [healthprobe] line through the REAL daemon into the session)
#          --alert (send alerts on failure: WhatsApp, then Telegram fallback;
#          deduped — re-alert hourly while failing, auto-resolve)
# Exit: 0 healthy, 1 one+ stage failed. Cron-friendly.
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEND="$SKILL_DIR/scripts/whatsapp-send.sh"
ENV_FILE="$SKILL_DIR/whatsapp.env"
STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/whatsapp-notify"
STATE_FILE="$STATE_DIR/health-state.json"
LOG="${WA_LISTEN_LOG:-/tmp/opencode/wa-listen.log}"
DLOG="/tmp/opencode/wa-watch-daemon.log"

cfg() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-; }
API_URL="${EVOLUTION_API_URL:-$(cfg EVOLUTION_API_URL)}"
API_KEY="${EVOLUTION_API_KEY:-$(cfg EVOLUTION_API_KEY)}"
INSTANCE="${EVOLUTION_INSTANCE:-$(cfg EVOLUTION_INSTANCE)}"

PROBE=0; ALERT=0
[[ "${1:-}" == "--probe" ]] && PROBE=1
[[ "${1:-}" == "--alert" ]] && ALERT=1
[[ "${2:-}" == "--alert" ]] && ALERT=1

fails=(); infos=()

# S1 — API + instance state
S1=$(curl -s --max-time 15 -H "apikey: $API_KEY" "$API_URL/instance/connectionState/$INSTANCE" 2>/dev/null | jq -r '.instance.state // "unreachable"' 2>/dev/null)
if [[ "$S1" != "open" ]]; then fails+=("S1 Evolution instance state: '$S1' (want open)"); else infos+=("S1 ok: open"); fi

# S2 — listener process + stdout inode + loop cycling
LP="$(cat "$STATE_DIR/listen.pid" 2>/dev/null || true)"
if [[ -n "$LP" ]] && kill -0 "$LP" 2>/dev/null; then
  MT=$(( $(date +%s) - $(stat -c %Y "$STATE_DIR/state.json" 2>/dev/null || echo 0) ))
  if [[ "$MT" -gt 30 ]]; then fails+=("S2 listener loop STUCK (state.json ${MT}s old)")
  else
    infos+=("S2 ok: pid $LP, loop ${MT}s")
    # emit() bypasses stdout, so an orphaned fd is cosmetic — but flag it
    ls -l /proc/$LP/fd/1 2>/dev/null | grep -q '(deleted)' && \
      infos+=("S2 warn: stdout orphaned (emit() unaffected; restart --listen for cleanliness)")
  fi
else fails+=("S2 listener DEAD (pidfile: ${LP:-none})"); fi

# S3 — watch daemon + its follow child
WP="$(cat "$STATE_DIR/watch.pid" 2>/dev/null || true)"
if [[ -n "$WP" ]] && kill -0 "$WP" 2>/dev/null; then
  if pgrep -f "whatsapp-send.sh --follow" >/dev/null 2>&1; then
    infos+=("S3 ok: daemon $WP + follow child")
  else fails+=("S3 daemon alive ($WP) but follow child MISSING — messages won't wake"); fi
else fails+=("S3 watch daemon DEAD (pidfile: ${WP:-none})"); fi

# S4 — inbound freshness: age of newest non-fromMe message in the store
NOW=$(date +%s)
LAST_IN=$(curl -s --max-time 20 -X POST "$API_URL/chat/findMessages/$INSTANCE" \
  -H "apikey: $API_KEY" -H 'Content-Type: application/json' \
  -d "{\"where\":{\"messageTimestamp\":{\"gte\":\"$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)\",\"lte\":\"$(date -u -d '+60 seconds' +%Y-%m-%dT%H:%M:%SZ)\"}},\"offset\":100,\"page\":1}" \
  | jq '[.messages.records[] | select(.key.fromMe == false) | .messageTimestamp] | max // 0' 2>/dev/null || echo 0)
AGE=$(( NOW - ${LAST_IN:-0} ))
if   [[ "$AGE" -gt 172800 ]]; then fails+=("S4 NO inbound message in $((AGE/3600))h — linked device may be desynced (restart instance + send test msg)")
elif [[ "$AGE" -gt 86400  ]]; then infos+=("S4 warn: last inbound $((AGE/3600))h ago")
else infos+=("S4 ok: last inbound $((AGE/60))min ago"); fi

# --probe: full local chain self-test (injects a healthprobe turn via the daemon)
if [[ "$PROBE" == 1 ]]; then
  MARK="healthprobe-$(date +%s)"
  echo "[wa] $(date +%Y-%m-%dT%H:%M:%S) from healthprobe (system): $MARK (self-test, ignore)" >> "$LOG"
  sleep 8
  if grep -q "$MARK" "$DLOG" 2>/dev/null; then
    infos+=("PROBE ok: daemon picked up + injected $MARK")
  else fails+=("PROBE FAILED: daemon did not inject $MARK within 8s"); fi
fi

# report
for i in "${infos[@]:-}"; do [[ -n "$i" ]] && echo "  ok   $i"; done
for f in "${fails[@]:-}"; do [[ -n "$f" ]] && echo "  FAIL $f"; done

if [[ ${#fails[@]} -gt 0 ]]; then
  if [[ "$ALERT" == 1 ]]; then
    KEY="$(printf '%s|' "${fails[@]}")"
    LAST_KEY="$(jq -r '.alert_key // ""' "$STATE_FILE" 2>/dev/null)"
    LAST_T="$(jq -r '.alert_ts // 0' "$STATE_FILE" 2>/dev/null)"
    NOWS=$(date +%s)
    if [[ "$KEY" != "$LAST_KEY" || $(( NOWS - LAST_T )) -gt 3600 ]]; then
      MSG="⚠️ WhatsApp chain unhealthy: ${fails[*]}"
      "$SEND" "$MSG" >/dev/null 2>&1 || true
      ~/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh "🔴 $MSG (WhatsApp alert path may also be down)" >/dev/null 2>&1 || true
      jq -n --arg k "$KEY" --argjson t "$NOWS" '{alert_key:$k, alert_ts:$t}' > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi
  fi
  exit 1
fi
# healthy again -> clear alert state
[[ -f "$STATE_FILE" ]] && rm -f "$STATE_FILE"
exit 0
