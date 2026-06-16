#!/usr/bin/env bash
# slugify.sh — turn a query into a filename-safe slug.
# Usage: ./slugify.sh "What is the current stable Bun version?"
# Output: whats-the-current-stable-bun-version
set -euo pipefail

input="${1:-}"
if [[ -z "$input" ]]; then
  echo "usage: $0 <query>" >&2
  exit 2
fi

# Transliterate non-ASCII where iconv is available; otherwise strip them.
# lowercase → keep alnum + space + hyphen → collapse whitespace to hyphen →
# squash repeats → trim leading/trailing hyphens → cap at 64 chars
if command -v iconv >/dev/null 2>&1; then
  transliterated=$(echo "$input" | iconv -f UTF-8 -t ASCII//TRANSLIT//IGNORE 2>/dev/null || echo "$input")
else
  transliterated="$input"
fi
slug=$(echo "$transliterated" \
  | tr '[:upper:]' '[:lower:]' \
  | tr -c 'a-z0-9 -' ' ' \
  | tr -s ' ' \
  | sed 's/ /-/g' \
  | sed 's/-\+/-/g' \
  | sed 's/^-//; s/-$//' \
  | cut -c1-64 \
  | sed 's/-$//')

if [[ -z "$slug" ]]; then
  slug="research"
fi

echo "$slug"
