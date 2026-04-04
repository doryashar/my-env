#!/usr/bin/env bash
COLS="${COLS:-${COLUMNS:-$(tput cols 2>/dev/null || echo 120)}}"

RST='\033[0m'
DIM='\033[2m'
B='\033[1m'
MAG='\033[1;35m'
CYN='\033[1;36m'
YLW='\033[1;33m'
GRN='\033[1;32m'
BLU='\033[1;34m'
BOX='\033[38;5;243m'
SEP='\033[38;5;238m'

# count visible (non-ANSI) character width
vlen() {
  printf '%b' "$1" | sed 's/\x1b\[[0-9;]*m//g' | wc -m | tr -d ' '
}

# left-pad text with spaces to reach target width
pad() {
  local text="$1" w="$2"
  local v; v=$(vlen "$text")
  local p=$((w - v))
  [[ $p -lt 0 ]] && p=0
  printf '%b' "$text"
  printf '%*s' "$p" ''
}

hrule() { printf "${BOX}"; printf '%*s' "$1" '' | tr ' ' '─'; printf "${RST}"; }
vsep()  { printf "${SEP}│${RST}"; }
emit()  { printf '%b\n' "$1"; }

K() { printf '  \e[1;32m%s\e[0m  %s' "$1" "$2"; }

# ── layout selection ────────────────────────────────────
if [[ $COLS -ge 110 ]]; then
  NC=3; C1=$(( (COLS-4)/3 )); C2=$C1; C3=$(( COLS - 2*C1 - 4 ))
elif [[ $COLS -ge 62 ]]; then
  NC=2; C1=$(( (COLS-2)/2 )); C2=$(( COLS - C1 - 2 )); C3=0
else
  NC=1; C1=$COLS; C2=0; C3=0
fi

# ── helpers ─────────────────────────────────────────────
title_box() {
  local t="$1"
  emit ""
  hrule "$((COLS-2))"; emit ""
  local left="${MAG}${B} ⌨  ${t}${RST}"
  local right="${DIM}Prefix: Ctrl+A  ·  Mouse: ON  ·  Copy mode: vi${RST}"
  local lv rv
  lv=$(vlen "$left")
  rv=$(vlen "$right")
  local mid=$(( COLS - 2 - lv - rv - 2 ))
  [[ $mid -lt 1 ]] && right="" && mid=$(( COLS - 2 - lv - 2 ))
  [[ $mid -lt 1 ]] && mid=0
  printf "${BOX}│${RST} %b%*s%b ${BOX}│${RST}\n" "$left" "$mid" '' "$right"
  hrule "$((COLS-2))"; emit ""
}

sec() {
  local a="$1" b="$2" c="$3"
  if [[ $NC -eq 3 ]]; then
    pad " ${YLW}${B}  $a${RST}" "$C1"; vsep
    pad " ${YLW}${B}  $b${RST}" "$C2"; vsep
    pad " ${YLW}${B}  $c${RST}" "$C3"; emit ""
    hrule "$C1"; vsep; hrule "$C2"; vsep; hrule "$C3"; emit ""
  elif [[ $NC -eq 2 ]]; then
    pad " ${YLW}${B}  $a${RST}" "$C1"; vsep
    pad " ${YLW}${B}  $b${RST}" "$C2"; emit ""
    hrule "$C1"; vsep; hrule "$C2"; emit ""
  else
    emit " ${YLW}${B}  $a${RST}"
    hrule "$C1"; emit ""
  fi
}

r() {
  local a="$1" b="$2" c="$3"
  if [[ $NC -eq 3 ]]; then
    pad "$a" "$C1"; vsep; pad "$b" "$C2"; vsep; pad "$c" "$C3"; emit ""
  elif [[ $NC -eq 2 ]]; then
    pad "$a" "$C1"; vsep; pad "$b" "$C2"; emit ""
  else
    pad "$a" "$C1"; emit ""
  fi
}

bl() {
  if [[ $NC -eq 3 ]]; then
    pad "" "$C1"; vsep; pad "" "$C2"; vsep; pad "" "$C3"; emit ""
  elif [[ $NC -eq 2 ]]; then
    pad "" "$C1"; vsep; pad "" "$C2"; emit ""
  else
    emit ""
  fi
}

sub() {
  if [[ $NC -eq 3 ]]; then
    pad "${MAG}  $1${RST}" "$C1"; vsep; pad "" "$C2"; vsep; emit ""
  elif [[ $NC -eq 2 ]]; then
    pad "${MAG}  $1${RST}" "$C1"; vsep; emit ""
  else
    emit "${MAG}  $1${RST}"
  fi
}

sxl() {
  local a="$1" b="$2" c="$3"
  if [[ $NC -eq 3 ]]; then
    pad "  $a" "$C1"; vsep; pad "  $b" "$C2"; vsep; pad "  $c" "$C3"; emit ""
  elif [[ $NC -eq 2 ]]; then
    pad "  $a" "$C1"; vsep; pad "  $b" "$C2"; emit ""
  else
    pad "  $a" "$C1"; emit ""
  fi
}

# ── content ─────────────────────────────────────────────

title_box "tmux Cheatsheet"

sec "SESSIONS" "WINDOWS" "MISC"
r "$(K '^A ^D' 'Detach')"           "$(K '^A ^C' 'New window (\$HOME)')" "$(K '^A K'  'Clear screen')"
r "$(K '^A S'  'Choose session')"   "$(K '^A w'  'List windows')"        "$(K '^A ^L' 'Refresh client')"
r "$(K '^A O'  'SessionX (zoxide)')" "$(K '^A H'  'Prev window')"        "$(K '^A :'  'Command prompt')"
bl                                "$(K '^A L'  'Next window')"         "$(K '^A R'  'Reload config')"
bl                                "$(K '^A ^A' 'Last window (toggle)')"
bl                                "$(K '^A r'  'Rename window')"
bl                                "$(K '^A \"'  'Choose window')"
emit ""

sec "PANES" "RESIZE (repeatable)" "COPY MODE (vi)"
r "$(K '^A s' 'Split horz (cwd)')"  "$(K '^A ,' 'Shrink left 20')" "$(K '^A [' 'Enter copy mode')"
r "$(K '^A v' 'Split vert (cwd)')"  "$(K '^A .' 'Grow right 20')"  "$(K 'v'   'Begin selection')"
r "$(K '^A |' 'Split horz (home)')" "$(K '^A -' 'Shrink down 7')"  "$(K 'y'   'Yank to clipboard')"
bl                                "$(K '^A =' 'Grow up 7')"
emit ""

sub "Navigate"
r "$(K '^A h' 'Left  ')$(K '^A l' 'Right')" "" ""
r "$(K '^A j' 'Down  ')$(K '^A k' 'Up   ')" "" ""
emit ""

sub "Other"
r "$(K '^A z' 'Zoom/unzoom')$(K '^A x' 'Swap')" "" ""
r "$(K '^A P' 'Pane borders')$(K '^A *' 'Sync')" "" ""
r "$(K '^A c' 'Kill pane')" "" ""
emit ""

sec "PLUGINS" "PLUGIN KEYS" ""
r "$(K 'tmux-thumbs'  'Hint overlays')"         "$(K '^A Space' 'thumbs pick')" ""
r "$(K 'tmux-fzf-url' 'Open URL from history')" "$(K '^A u'     'fzf-url')"     ""
r "$(K 'tmux-fzf'     'Interactive fzf menu')"  "$(K '^A F'     'fzf menu')"     ""
r "$(K 'floax'        'Floating scratchpad')"   "$(K '^A p'     'floax open')"   ""
r ""                                          "$(K '^A P'     'floax menu')"   ""
emit ""

INNER=$((COLS - 2))
hrule "$INNER"; emit ""
pad " ${BLU}${B}  SESSIONX — keybindings inside the picker${RST}" "$INNER"; emit ""
hrule "$INNER"; emit ""
emit ""

sxl "$(K 'Enter'    'Accept session')" "$(K 'Ctrl-e' 'New from PWD')" "$(K 'Ctrl-b' 'Back')"
sxl "$(K 'Esc'      'Abort')"          "$(K 'Ctrl-w' 'Windows')"       "$(K '?'      'Preview')"
sxl "$(K 'Ctrl-y'   'Zoxide query')"   "$(K 'Ctrl-t' 'Tree mode')"     "$(K 'Ctrl-n/p' 'Navigate')"
sxl "$(K 'Alt+Bksp' 'Kill session')"   "$(K 'Ctrl-x' 'Config paths')"  ""
sxl ""                                "$(K 'Ctrl-r' 'Rename session')" ""
emit ""
