#!/bin/bash
# secrets_health.sh — check how old the encrypted secrets backup is and
# alert (Telegram, at most once a day) when it goes stale. The encrypted
# backup (scripts/sync/sync_encrypted.sh) is a human step on purpose; this
# script only watches. Run by secrets-health.timer.
#
# Exit codes: 0 = fresh, 1 = stale, 2 = no backup has ever run.

set -uo pipefail

ENV_DIR="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
SECRETS_HASH_FILE="${SECRETS_HASH_FILE:-$ENV_DIR/var/local_hashes}"
SECRETS_MAX_AGE_HOURS="${SECRETS_MAX_AGE_HOURS:-48}"
SECRETS_NOTIFY="${SECRETS_NOTIFY:-1}"
SECRETS_SEND="${SECRETS_SEND:-/home/yashar/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh}"
SECRETS_ENV_FILE="${SECRETS_ENV_FILE:-/home/yashar/.config/ailaw-pr-review/env}"
SECRETS_PING_FILE="${SECRETS_PING_FILE:-$ENV_DIR/tmp/secrets-health.ping}"
SECRETS_PING_EVERY_SECONDS="${SECRETS_PING_EVERY_SECONDS:-86400}"

# send at most once per SECRETS_PING_EVERY_SECONDS; a failed send leaves
# the ping file untouched and does not affect the exit code
send_alert() {
    local message="$1"
    [ "$SECRETS_NOTIFY" = "1" ] || return 0
    local need_ping=0
    if [ ! -f "$SECRETS_PING_FILE" ]; then
        need_ping=1
    else
        local now ping_age
        now=$(date +%s)
        ping_age=$(( now - $(stat -c %Y "$SECRETS_PING_FILE") ))
        [ "$ping_age" -ge "$SECRETS_PING_EVERY_SECONDS" ] && need_ping=1
    fi
    [ "$need_ping" -eq 1 ] || return 0
    if [ -f "$SECRETS_ENV_FILE" ]; then
        set -a
        source "$SECRETS_ENV_FILE"
        set +a
    fi
    [ -f "$SECRETS_SEND" ] || return 0
    if "$SECRETS_SEND" --loud "🔒 $message"; then
        mkdir -p "$(dirname "$SECRETS_PING_FILE")"
        touch "$SECRETS_PING_FILE"
    fi
    return 0
}

main() {
    if [ ! -f "$SECRETS_HASH_FILE" ]; then
        local message="SECRETS BACKUP: no secrets backup has ever run on this machine (var/local_hashes is missing). Run: ~/env/scripts/sync/sync_encrypted.sh"
        echo "secrets_health: $message" >&2
        send_alert "$message"
        exit 2
    fi

    local now age_seconds age_hours days hours
    now=$(date +%s)
    age_seconds=$(( now - $(stat -c %Y "$SECRETS_HASH_FILE") ))
    [ "$age_seconds" -lt 0 ] && age_seconds=0
    age_hours=$(( age_seconds / 3600 ))
    if [ "$age_hours" -le "$SECRETS_MAX_AGE_HOURS" ]; then
        echo "secrets backup is ${age_hours}h old (limit ${SECRETS_MAX_AGE_HOURS}h)"
        exit 0
    fi

    days=$(( age_hours / 24 ))
    hours=$(( age_hours % 24 ))
    local message="SECRETS BACKUP STALE: the last backup was ${days} days ${hours}h ago (limit ${SECRETS_MAX_AGE_HOURS}h). Secrets changed since then are not backed up. Run: ~/env/scripts/sync/sync_encrypted.sh"
    echo "secrets_health: $message" >&2
    send_alert "$message"
    exit 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
