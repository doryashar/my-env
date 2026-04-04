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

vlen() { printf '%b' "$1" | sed 's/\x1b\[[0-9;]*m//g' | wc -m | tr -d ' '; }

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

if [[ $COLS -ge 110 ]]; then
  NC=3; C1=$(( (COLS-4)/3 )); C2=$C1; C3=$(( COLS - 2*C1 - 4 ))
elif [[ $COLS -ge 62 ]]; then
  NC=2; C1=$(( (COLS-2)/2 )); C2=$(( COLS - C1 - 2 )); C3=0
else
  NC=1; C1=$COLS; C2=0; C3=0
fi

title_box() {
  local t="$1"
  emit ""
  hrule "$((COLS-2))"; emit ""
  local left="${MAG}${B} ⌨  ${t}${RST}"
  local right="${DIM}Leader: Space  ·  Kickstart (Lazy)  ·  tokyonight${RST}"
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

title_box "nvim Cheatsheet"

sec "LEADER + SEARCH" "LEADER + GIT HUNK" "LEADER + TOGGLE"
r "$(K 'sp sf' 'Files')"                "$(K 'ph hs' 'Stage hunk')"          "$(K 'pt th' 'Inlay hints')"
r "$(K 'sp sg' 'Live grep')"            "$(K 'ph hr' 'Reset hunk')"          "$(K 'pt tb' 'Blame line')"
r "$(K 'sp sw' 'Current word')"         "$(K 'ph hS' 'Stage buffer')"        "$(K 'pt tD' 'Show deleted')"
r "$(K 'sp s/' 'Grep open files')"      "$(K 'ph hu' 'Undo stage hunk')"     ""
r "$(K 'sp sd' 'Diagnostics')"          "$(K 'ph hR' 'Reset buffer')"        ""
r "$(K 'sp sr' 'Resume search')"        "$(K 'ph hp' 'Preview hunk')"        ""
r "$(K 'sp s.' 'Recent files')"         "$(K 'ph hb' 'Blame line')"          ""
r "$(K 'sp sn' 'Neovim config')"        "$(K 'ph hd' 'Diff vs index')"       ""
r "$(K 'sp sh' 'Help tags')"            "$(K 'ph hD' 'Diff vs last')"        ""
r "$(K 'sp sk' 'Keymaps')"              ""                                  ""
r "$(K 'sp ss' 'Telescope picker')"     ""                                  ""
r "$(K 'SPC SPC' 'Buffers')"            ""                                  ""
r "$(K 'sp /' 'Fuzzy in buffer')"       ""                                  ""
emit ""

sec "LSP  (gd/gr/gI/gD)" "WINDOW NAV" "MISC"
r "$(K 'gd'  'Goto definition')"        "$(K 'C-h' 'Focus left')"            "$(K 'Esc'  'Clear search hl')"
r "$(K 'gr'  'Goto references')"        "$(K 'C-l' 'Focus right')"           "$(K 'sp f' 'Format buffer')"
r "$(K 'gI'  'Goto implementation')"    "$(K 'C-j' 'Focus down')"            "$(K 'sp q' 'Diagnostic list')"
r "$(K 'gD'  'Goto declaration')"       "$(K 'C-k' 'Focus up')"              "$(K '\\\\'  'NeoTree reveal')"
r "$(K 'sp D'  'Type definition')"      ""                                  ""
r "$(K 'sp ds' 'Document symbols')"     ""                                  ""
r "$(K 'sp ws' 'Workspace symbols')"    ""                                  ""
r "$(K 'sp rn' 'Rename symbol')"        ""                                  ""
r "$(K 'sp ca' 'Code action')"          ""                                  ""
emit ""

sec "COMPLETION (insert mode)" "DEBUG (DAP)" "GIT NAV"
r "$(K 'C-n / C-p' 'Next/prev item')"  "$(K 'F5'  'Start/continue')"        "$(K ']c' 'Next git change')"
r "$(K 'C-b / C-f' 'Docs back/fwd')"   "$(K 'F1'  'Step into')"             "$(K '[c' 'Prev git change')"
r "$(K 'C-y'  'Confirm')"               "$(K 'F2'  'Step over')"             ""
r "$(K 'C-Spc' 'Manual complete')"      "$(K 'F3'  'Step out')"              ""
r "$(K 'C-l'  'Snippet next')"          "$(K 'F7'  'Toggle DAP UI')"         ""
r "$(K 'C-h'  'Snippet prev')"          "$(K 'sp b' 'Toggle breakpoint')"    ""
bl                                      "$(K 'sp B' 'Set breakpoint')"       ""
emit ""
