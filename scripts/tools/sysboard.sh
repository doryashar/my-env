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
SECTION_LABELS=("System Services" "User Services" Timers Docker Cron Autostart)
TAB_LABELS=(Sys Usr Timers Dkr Cron Auto)

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

# collect_timers [user] -> NEXT<TAB>LAST<TAB>UNIT
# Per-unit `systemctl show` instead of parsing list-timers columns
# (column widths vary; "n/a" breaks positional parsing).
collect_timers() {
  local scope=()
  [[ "${1:-}" == "user" ]] && scope=(--user)
  systemctl "${scope[@]}" list-units --type=timer --all --no-legend 2>/dev/null \
    | awk 'NF{print $1}' \
    | while read -r unit; do
        local next last
        next=$(systemctl "${scope[@]}" show "$unit" --property=NextElapseUSecRealtime --value 2>/dev/null)
        last=$(systemctl "${scope[@]}" show "$unit" --property=LastTriggerUSec --value 2>/dev/null)
        printf '%s\t%s\t%s\n' "${next:-n/a}" "${last:-n/a}" "$unit"
      done
}

# map docker status string -> coarse state (running/exited/created/...)
docker_state_from_status() {
  case "$1" in
    *" (Paused)") echo paused ;;
    Up*)         echo running ;;
    Exited*)     echo exited ;;
    Created*)    echo created ;;
    Restarting*) echo restarting ;;
    Paused*)     echo paused ;;
    *)           echo other ;;
  esac
}

# collect_docker -> STATE<TAB>NAME<TAB>IMAGE<TAB>STATUS<TAB>PORTS
collect_docker() {
  local name image status ports
  while IFS=$'\t' read -r name image status ports; do
    [[ -z "$name" ]] && continue
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$(docker_state_from_status "$status")" "$name" "$image" "$status" "$ports"
  done < <(docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null)
}

# cron_parse_line LINE user|system -> SCHEDULE<TAB>WHO<TAB>COMMAND (rc 1 = skip)
cron_parse_line() {
  local line="$1" src="$2"
  [[ "$line" =~ ^[[:space:]]*(#|$) ]] && return 1
  [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*= ]] && return 1
  local first rest who cmd sched
  read -r first rest <<<"$line"
  if [[ "$first" == @* ]]; then
    sched="$first"
    if [[ "$src" == "user" ]]; then
      who="${USER:-$(id -un)}"; cmd="$rest"
    else
      read -r who cmd <<<"$rest"
    fi
  else
    local m h dom mon dow
    read -r m h dom mon dow rest <<<"$line"
    sched="$m $h $dom $mon $dow"
    if [[ "$src" == "user" ]]; then
      who="${USER:-$(id -un)}"; cmd="$rest"
    else
      read -r who cmd <<<"$rest"
    fi
  fi
  printf '%s\t%s\t%s\n' "$sched" "$who" "$cmd"
}

# collect_cron [CRON_D_DIR] -> SOURCE<TAB>SCHEDULE<TAB>WHO<TAB>COMMAND
# SOURCE is "user" or the /etc/cron.d file path.
collect_cron() {
  local cron_d_dir="${1:-${SYSBOARD_CRON_D:-/etc/cron.d}}"
  local out line entry file
  if out=$(crontab -l 2>/dev/null); then
    while IFS= read -r line; do
      if entry=$(cron_parse_line "$line" user); then
        printf 'user\t%s\n' "$entry"
      fi
    done <<<"$out"
  fi
  for file in "$cron_d_dir"/*; do
    [[ -f "$file" && -r "$file" ]] || continue
    while IFS= read -r line; do
      if entry=$(cron_parse_line "$line" system); then
        printf '%s\t%s\n' "$file" "$entry"
      fi
    done <"$file"
  done
}

# autostart_parse_desktop FILE user|system -> STATE<TAB>NAME<TAB>EXEC<TAB>SCOPE<TAB>FILEPATH
autostart_parse_desktop() {
  local file="$1" scope="$2"
  local name="" exec_cmd="" hidden="false" autostart="true" key value
  while IFS='=' read -r key value; do
    key="${key//[[:space:]]/}"
    case "$key" in
      Name) name="$value" ;;
      Exec) exec_cmd="$value" ;;
      Hidden) hidden="$value" ;;
      X-GNOME-Autostart-enabled) autostart="$value" ;;
    esac
  done <"$file"
  local state="enabled"
  [[ "$hidden" == "true" ]] && state="hidden"
  [[ "$autostart" == "false" ]] && state="disabled"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$state" "${name:-$(basename "$file" .desktop)}" "$exec_cmd" "$scope" "$file"
}

# collect_autostart [USER_DIR] [SYSTEM_DIR] -> STATE<TAB>NAME<TAB>EXEC<TAB>SCOPE<TAB>FILEPATH
collect_autostart() {
  local user_dir="${1:-${SYSBOARD_USER_AUTOSTART:-$HOME/.config/autostart}}"
  local system_dir="${2:-${SYSBOARD_SYSTEM_AUTOSTART:-/etc/xdg/autostart}}"
  local f
  for f in "$user_dir"/*.desktop; do
    [[ -f "$f" ]] && autostart_parse_desktop "$f" user
  done
  for f in "$system_dir"/*.desktop; do
    [[ -f "$f" ]] && autostart_parse_desktop "$f" system
  done
}

# ---- formatting / report ----

sb_state_color() {
  case "$1" in
    active|running|enabled) echo "$GREEN" ;;
    activating)             echo "$YELLOW" ;;
    failed)                 echo "$RED" ;;
    *)                      echo "$GRAY" ;;
  esac
}

# sb_row_state SECTION ROW -> state word ("" when section has no state)
sb_row_state() {
  local a
  IFS=$'\t' read -r a _ <<<"$2"
  case "$1" in
    system|user|docker|autostart) echo "$a" ;;
    *) echo "" ;;
  esac
}

# sb_row_color SECTION ROW -> ANSI color for the row ("" = default)
sb_row_color() {
  local section="$1" row="$2"
  if [[ "$section" == "autostart" ]]; then
    local scope
    IFS=$'\t' read -r _ _ _ scope _ <<<"$row"
    [[ "$scope" == "system" ]] && { echo "$GRAY"; return; }
  fi
  local st
  st=$(sb_row_state "$section" "$row")
  [[ -z "$st" ]] && { echo ""; return; }
  sb_state_color "$st"
}

sb_truncate() {
  local s="$1" w="$2"
  if (( ${#s} > w )); then s="${s:0:$((w - 1))}…"; fi
  printf '%s' "$s"
}

sb_format_row() {
  local section="$1"
  local a b c d e
  IFS=$'\t' read -r a b c d e <<<"$2"
  case "$section" in
    system|user) printf '%-14s %-42s %s' "$a/$b" "$c" "$d" ;;
    timers)      printf '%-25s %-25s %s' "$a" "last: $b" "$c" ;;
    docker)      printf '%-10s %-24s %-24s %s' "$a" "$b" "$c" "$e" ;;
    cron)        printf '%-21s %-15s %-10s %s' "$(basename "$a")" "$b" "$c" "$d" ;;
    autostart)   printf '%-9s %-26s [%s] %s' "$a" "$b" "$d" "$c" ;;
  esac
}

# sb_collect_one SECTION -> raw TSV rows for that section name
sb_collect_one() {
  case "$1" in
    system)    collect_systemd ;;
    user)      collect_systemd user ;;
    timers)    printf '%s\n%s' "$(collect_timers)" "$(collect_timers user)" ;;
    docker)    collect_docker ;;
    cron)      collect_cron ;;
    autostart) collect_autostart ;;
  esac
}

sb_render_report() {
  local i=1 section rows row color
  for section in "${SECTIONS[@]}"; do
    if [[ -n "$SECTION_FILTER" && "$section" != "$SECTION_FILTER" ]]; then
      i=$((i + 1)); continue
    fi
    printf '\n%b== %s ==%b\n' "$BOLD" "${SECTION_LABELS[$((i - 1))]}" "$NC"
    rows=$(sb_collect_one "$section")
    if [[ "$section" == "docker" ]] && ! command -v docker &>/dev/null; then
      echo "  (docker not installed)"
    elif [[ -z "${rows//$'\n'/}" ]]; then
      echo "  (none)"
    else
      while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        color=$(sb_row_color "$section" "$row")
        printf '  '
        [[ -n "$color" ]] && printf '%b' "$color"
        sb_format_row "$section" "$row"
        printf '%b\n' "$NC"
      done <<<"$rows"
    fi
    i=$((i + 1))
  done
}

# ---- TUI ----

sb_tty_ok() {
  # /dev/tty is mode 666 everywhere, so -r is always true; probe by
  # actually opening it (fails with no controlling terminal, e.g. setsid)
  { : </dev/tty; } 2>/dev/null
}

sb_input() {
  # read one key from /dev/tty when available, else stdin
  # SB_INPUT_RC records read's exit code: 1 = EOF, >128 = timeout
  SB_INPUT_RC=0
  local t=()
  [[ $AUTO_REFRESH -eq 1 ]] && t=(-t "$REFRESH_INTERVAL")
  if sb_tty_ok; then
    IFS= read -rsn1 ${t[@]+"${t[@]}"} "$1" </dev/tty || SB_INPUT_RC=$?
  else
    IFS= read -rsn1 ${t[@]+"${t[@]}"} "$1" || SB_INPUT_RC=$?
  fi
}

sb_read_key() {
  SB_KEY=""
  sb_input SB_KEY
  if [[ "$SB_KEY" == $'\e' ]]; then
    local seq=""
    if sb_tty_ok; then
      IFS= read -rsn2 -t 0.1 seq </dev/tty || true
    else
      IFS= read -rsn2 -t 0.1 seq || true
    fi
    case "$seq" in
      '[A') SB_KEY='k' ;;
      '[B') SB_KEY='j' ;;
      *)    SB_KEY='' ;;
    esac
  fi
}

sb_refresh_counts() {
  local section rows n
  for section in "${SECTIONS[@]}"; do
    rows=$(sb_collect_one "$section")
    n=$(printf '%s' "$rows" | grep -c . || true)
    if [[ "$section" == "docker" ]]; then
      local running
      running=$(printf '%s' "$rows" | grep -c '^running' || true)
      SB_COUNTS[docker]="$running/$n"
    else
      SB_COUNTS[$section]="$n"
    fi
  done
}

sb_load_section() {
  SB_ROWS=()
  local rows
  rows=$(sb_collect_one "${SECTIONS[$((SB_SECTION - 1))]}")
  if [[ -n "${rows//$'\n'/}" ]]; then
    mapfile -t SB_ROWS <<<"$rows"
    local filtered=() r
    for r in "${SB_ROWS[@]}"; do
      [[ -n "$r" ]] && filtered+=("$r")
    done
    SB_ROWS=("${filtered[@]+"${filtered[@]}"}")
  fi
  (( SB_SEL >= ${#SB_ROWS[@]} )) && SB_SEL=$(( ${#SB_ROWS[@]} - 1 ))
  (( SB_SEL < 0 )) && SB_SEL=0
}

sb_summary_line() {
  printf '%bSYS%b %s ▪ USR %s ▪ TIMER %s ▪ DKR %s ▪ CRON %s ▪ AUTO %s%b' \
    "$BOLD" "$NC" "${SB_COUNTS[system]:-?}" "${SB_COUNTS[user]:-?}" \
    "${SB_COUNTS[timers]:-?}" "${SB_COUNTS[docker]:-?}" \
    "${SB_COUNTS[cron]:-?}" "${SB_COUNTS[autostart]:-?}" "$NC"
}

sb_draw() {
  local cols lines
  cols=$(tput cols 2>/dev/null || echo 80)
  lines=$(tput lines 2>/dev/null || echo 24)
  printf '\033[H\033[2J'
  printf '%b sysboard %b' "$BOLD" "$NC"
  local n=1 tabstr=""
  for n in "${!SECTION_LABELS[@]}"; do
    if [[ $((n + 1)) -eq $SB_SECTION ]]; then
      tabstr+="\033[7m[$((n + 1)):${TAB_LABELS[n]}]\033[0m "
    else
      tabstr+="[$((n + 1)):${TAB_LABELS[n]}] "
    fi
  done
  printf '%b\n' "$tabstr"
  printf '%b\n' "$(sb_summary_line)"
  printf '%*s\n' "$cols" '' | tr ' ' '-'
  local height=$((lines - 6))
  local first=0
  if [[ $SB_SEL -ge $height ]]; then first=$((SB_SEL - height + 1)); fi
  local section="${SECTIONS[$((SB_SECTION - 1))]}"
  local i idx color line
  for ((i = 0; i < height; i++)); do
    idx=$((first + i))
    if [[ $idx -ge ${#SB_ROWS[@]} ]]; then
      printf '\n'
      continue
    fi
    line=$(sb_format_row "$section" "${SB_ROWS[$idx]}")
    if [[ $idx -eq $SB_SEL ]]; then
      printf '\033[7m %s\033[0m\n' "$(sb_truncate "$line" $((cols - 2)))"
    else
      color=$(sb_row_color "$section" "${SB_ROWS[$idx]}")
      [[ -n "$color" ]] && printf '%b' "$color"
      printf ' %s' "$(sb_truncate "$line" $((cols - 2)))"
      printf '%b\n' "$NC"
    fi
  done
  printf '%*s\n' "$cols" '' | tr ' ' '-'
  printf '%bj/k move · 1-6/tab section · s/t/r start/stop/restart · e enable%b\n' "$GRAY" "$NC"
  printf '%bl logs · R refresh · ? help · q quit%b\n' "$GRAY" "$NC"
  [[ -n "$SB_MSG" ]] && printf '%b%s%b\n' "$YELLOW" "$(sb_truncate "$SB_MSG" $((cols - 2)))" "$NC"
}

sb_confirm() {
  SB_MSG="$1 [y/N]"
  sb_draw
  local key=""
  sb_input key
  [[ "$key" == "y" || "$key" == "Y" ]]
}

# ---- TUI actions ----

sb_section_name() { echo "${SECTIONS[$((SB_SECTION - 1))]}"; }

sb_selected_unit() {
  local row="${SB_ROWS[$SB_SEL]:-}"
  local a b c
  IFS=$'\t' read -r a b c _ <<<"$row"
  case "$(sb_section_name)" in
    system|user|timers) echo "$c" ;;
    docker)             echo "$b" ;;
    *)                  echo "" ;;
  esac
}

sb_unit_scope() {
  # echoes "--user" if unit lives on the user bus, else "" (system)
  if systemctl --user cat "$1" &>/dev/null; then echo "--user"; else echo ""; fi
}

sb_systemd_action() {
  local verb="$1"
  local unit scope=()
  unit=$(sb_selected_unit)
  [[ -z "$unit" ]] && return 1
  case "$(sb_section_name)" in
    user)   scope=(--user) ;;
    timers) [[ -n "$(sb_unit_scope "$unit")" ]] && scope=(--user) ;;
  esac
  sb_confirm "$verb $unit?" || return 1
  local rc=0
  if [[ ${#scope[@]} -eq 0 ]]; then
    tput rmcup 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    sudo systemctl "$verb" "$unit"
    rc=$?
    tput civis 2>/dev/null || true
    tput smcup 2>/dev/null || true
  else
    systemctl --user "$verb" "$unit"
    rc=$?
  fi
  SB_MSG="$verb $unit -> exit $rc"
  sb_refresh_counts
  sb_load_section
}

sb_toggle_enable() {
  local unit scope=() cur
  unit=$(sb_selected_unit)
  [[ -z "$unit" ]] && return 1
  case "$(sb_section_name)" in
    user)   scope=(--user) ;;
    timers) [[ -n "$(sb_unit_scope "$unit")" ]] && scope=(--user) ;;
  esac
  cur=$(systemctl "${scope[@]}" is-enabled "$unit" 2>/dev/null || echo unknown)
  if [[ "$cur" == "enabled" ]]; then
    sb_systemd_action disable
  else
    sb_systemd_action enable
  fi
}

sb_docker_action() {
  local verb="$1" name
  name=$(sb_selected_unit)
  [[ -z "$name" ]] && return 1
  sb_confirm "docker $verb $name?" || return 1
  docker "$verb" "$name" &>/dev/null
  local rc=$?
  SB_MSG="docker $verb $name -> exit $rc"
  sb_refresh_counts
  sb_load_section
}

sb_show_logs() {
  local unit section scope=()
  section=$(sb_section_name)
  unit=$(sb_selected_unit)
  [[ -z "$unit" ]] && return 1
  sb_confirm "show logs for $unit?"
  tput rmcup 2>/dev/null || true
  tput cnorm 2>/dev/null || true
  if [[ "$section" == "docker" ]]; then
    docker logs --tail 200 "$unit" | "${PAGER:-less}"
  else
    case "$section" in
      user)   scope=(--user) ;;
      timers) [[ -n "$(sb_unit_scope "$unit")" ]] && scope=(--user) ;;
    esac
    journalctl "${scope[@]}" -u "$unit" -n 200 --no-pager | "${PAGER:-less}"
  fi
  tput civis 2>/dev/null || true
  tput smcup 2>/dev/null || true
}

sb_handle_action() {
  SB_MSG=""
  case "$(sb_section_name)" in
    system|user|timers)
      case "$1" in
        s) sb_systemd_action stop ;;
        t) sb_systemd_action start ;;
        r) sb_systemd_action restart ;;
        e) sb_toggle_enable ;;
        l) sb_show_logs ;;
      esac
      ;;
    docker)
      case "$1" in
        s) sb_docker_action stop ;;
        t) sb_docker_action start ;;
        r) sb_docker_action restart ;;
        l) sb_show_logs ;;
        *) SB_MSG="read-only action" ;;
      esac
      ;;
    *)
      SB_MSG="read-only section"
      ;;
  esac
}

sb_help_overlay() {
  local box=(
    'sysboard keys'
    ''
    '  j/k or arrows   move selection'
    '  1-6 or Tab      switch section'
    '  g / G           jump to top / bottom'
    '  s / t / r       stop / start / restart'
    '  e               toggle enable/disable (systemd)'
    '  l               view logs (journalctl / docker logs)'
    '  R               refresh now'
    '  q               quit'
    ''
    '  cron and autostart sections are read-only'
  )
  local lines cols i
  lines=$(tput lines 2>/dev/null || echo 24)
  cols=$(tput cols 2>/dev/null || echo 80)
  local top=$(((lines - ${#box[@]}) / 2))
  printf '\033[H'
  for ((i = 0; i < top; i++)); do printf '\n'; done
  printf '%*s┌─ help ─┐\n' $(((cols - 10) / 2)) ''
  for i in "${box[@]}"; do
    printf '%*s│ %s │\n' $(((cols - 10) / 2)) '' "$(sb_truncate "$i" $((cols - 16)))"
  done
  printf '%*s└────────┘\n' $(((cols - 10) / 2)) ''
  printf 'press any key...'
  local key=""
  sb_input key
}

sb_tui() {
  tput smcup 2>/dev/null || true
  tput civis 2>/dev/null || true
  trap 'tput cnorm 2>/dev/null; tput rmcup 2>/dev/null; exit 0' INT TERM
  SB_SECTION=$START_SECTION
  SB_SEL=0
  sb_refresh_counts
  sb_load_section
  while true; do
    sb_draw
    sb_read_key
    if [[ -z "$SB_KEY" ]]; then
      if (( SB_INPUT_RC > 0 && SB_INPUT_RC < 128 )); then
        sleep 1   # stdin EOF (non-interactive) — avoid busy spin
      fi
      sb_refresh_counts
      sb_load_section
      continue
    fi
    case "$SB_KEY" in
      q) break ;;
      j) (( SB_SEL < ${#SB_ROWS[@]} - 1 )) && SB_SEL=$((SB_SEL + 1)) ;;
      k) (( SB_SEL > 0 )) && SB_SEL=$((SB_SEL - 1)) ;;
      g) SB_SEL=0 ;;
      G) SB_SEL=$(( ${#SB_ROWS[@]} - 1 )) ;;
      [1-6])
        SB_SECTION="$SB_KEY"
        SB_SEL=0
        sb_load_section
        ;;
      $'\t')
        SB_SECTION=$(( SB_SECTION % ${#SECTIONS[@]} + 1 ))
        SB_SEL=0
        sb_load_section
        ;;
      R)
        sb_refresh_counts
        sb_load_section
        SB_MSG="refreshed $(date +%H:%M:%S)"
        ;;
      s|t|r|e|l) sb_handle_action "$SB_KEY" ;;
      '?') sb_help_overlay ;;
    esac
  done
  tput cnorm 2>/dev/null || true
  tput rmcup 2>/dev/null || true
}

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
