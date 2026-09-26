#!/usr/bin/env bash
# sysboard - TUI dashboard for systemd services, timers, docker, cron, autostart
# Usage: sysboard [--report] [--section NAME] [--no-auto] [--refresh N] [-h]
set -uo pipefail

# ---- colors (mirrors functions/logging.sh) ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
GRAY='\033[90m'
BOLD='\033[1m'
NC='\033[0m'

# ---- configuration / globals ----
MODE="tui"
SECTION_FILTER=""
AUTO_REFRESH=1
REFRESH_INTERVAL=5
START_SECTION=1

SECTIONS=(system user timers docker cron autostart)
SECTION_LABELS=(System User Timers Docker Cron Autostart)

SB_SECTION=1
SB_SEL=0
SB_ROWS=()
SB_MSG=""
SB_KEY=""
declare -A SB_COUNTS

sb_usage() {
  cat <<'EOF'
sysboard - dashboard for services, timers, docker, cron, autostart

Usage: sysboard [options]

Options:
  --report          print all sections and exit (pretty, colored)
  --section NAME    report mode: show only that section; TUI mode: start on it
                    (system|user|timers|docker|cron|autostart)
  --no-auto         disable auto-refresh (TUI)
  --refresh N       auto-refresh interval in seconds (default 5)
  -h, --help        show this help

TUI keys:
  j/k or arrows  move   1-6/Tab  switch section   R  refresh
  s stop  t start  r restart  e enable/disable  l logs  q quit
EOF
}

sb_section_index() {
  # echoes 1-based index for a section name, or nothing if invalid
  local i=1 name
  for name in "${SECTIONS[@]}"; do
    [[ "$name" == "$1" ]] && { echo "$i"; return 0; }
    i=$((i + 1))
  done
  return 1
}

sb_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --report)
        MODE="report"
        ;;
      --section)
        if [[ -z "${2:-}" ]] || ! sb_section_index "$2" >/dev/null; then
          echo "sysboard: --section requires one of: ${SECTIONS[*]}" >&2
          return 1
        fi
        SECTION_FILTER="$2"
        START_SECTION=$(sb_section_index "$2")
        shift
        ;;
      --no-auto)
        AUTO_REFRESH=0
        ;;
      --refresh)
        if [[ ! "${2:-}" =~ ^[0-9]+$ || "${2:-0}" -eq 0 ]]; then
          echo "sysboard: --refresh requires a positive integer" >&2
          return 1
        fi
        REFRESH_INTERVAL="$2"
        shift
        ;;
      -h|--help)
        sb_usage
        exit 0
        ;;
      *)
        echo "sysboard: unknown option: $1" >&2
        return 1
        ;;
    esac
    shift
  done
}

# ---- collectors: emit TSV rows, one entry per line ----

# collect_systemd [user] -> ACTIVE<TAB>SUB<TAB>UNIT<TAB>ENABLED
collect_systemd() {
  local scope=()
  [[ "${1:-}" == "user" ]] && scope=(--user)
  local unit state
  declare -A enabled_map=()
  while read -r unit state; do
    [[ -n "$unit" ]] && enabled_map["$unit"]="$state"
  done < <(systemctl "${scope[@]}" list-unit-files --type=service --no-legend 2>/dev/null | awk 'NF{print $1, $2}')
  systemctl "${scope[@]}" list-units --type=service --all --no-legend 2>/dev/null \
    | awk 'NF{print $3 "\t" $4 "\t" $1}' \
    | while IFS=$'\t' read -r active sub unit; do
        printf '%s\t%s\t%s\t%s\n' "$active" "$sub" "$unit" "${enabled_map[$unit]:-static}"
      done
}

sb_render_report() { echo "(not implemented yet)"; }
sb_tui() { echo "(not implemented yet)"; }

sb_main() {
  sb_parse_args "$@" || { sb_usage >&2; return 1; }
  if [[ "$MODE" == "tui" && ! -t 0 && -z "${SYSBOARD_FORCE_TUI:-}" ]]; then
    echo "sysboard: stdin is not a terminal, falling back to report mode" >&2
    MODE="report"
  fi
  if [[ "$MODE" == "report" ]]; then
    sb_render_report
    return $?
  fi
  sb_tui
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  sb_main "$@"
fi
