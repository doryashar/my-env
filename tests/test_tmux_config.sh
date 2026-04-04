#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_CONF="$SCRIPT_DIR/../dotfiles/.tmux.conf"
RESET_CONF="$SCRIPT_DIR/../config/tmux/tmux.reset.conf"

FAILURES=0
PASS=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; echo "    $2"; FAILURES=$((FAILURES + 1)); }

echo "=== .tmux.conf tests ==="

grep -q "default-terminal 'tmux-256color'" "$TMUX_CONF" && \
  pass "truecolor default-terminal set" || \
  fail "truecolor default-terminal" "missing"

grep -q 'default-terminal.*\$TERM' "$TMUX_CONF" && \
  fail "stale default-terminal override" "line clobbers truecolor" || \
  pass "no stale default-terminal override"

grep -q "focus-events on" "$TMUX_CONF" && \
  pass "focus-events enabled" || \
  fail "focus-events" "missing"

grep -q "allow-passthrough on" "$TMUX_CONF" && \
  pass "allow-passthrough enabled" || \
  fail "allow-passthrough" "missing"

grep "^set -g @plugin 'tmux-plugins/tmux-resurrect'" "$TMUX_CONF" > /dev/null && \
  pass "tmux-resurrect is uncommented" || \
  fail "tmux-resurrect" "commented out but continuum-restore is on"

grep "^set -g @catppuccin_flavor 'mocha'" "$TMUX_CONF" > /dev/null && \
  pass "catppuccin flavor explicit" || \
  fail "catppuccin flavor" "should be explicitly set"

grep -q "^bind c new-window" "$TMUX_CONF" && \
  pass "c = new-window (post-tpm override)" || \
  fail "bind c" "should be new-window, after tpm"

grep -q "^bind x kill-pane" "$TMUX_CONF" && \
  pass "x = kill-pane (post-tpm override)" || \
  fail "bind x" "should be kill-pane, after tpm"

grep -q "^bind X kill-window" "$TMUX_CONF" && \
  pass "X = kill-window" || \
  fail "bind X" "missing"

grep -q "^bind C new-session" "$TMUX_CONF" && \
  pass "C = new-session" || \
  fail "bind C" "missing"

grep -q "^bind \[ copy-mode" "$TMUX_CONF" && \
  pass "[ = copy-mode" || \
  fail "bind [" "missing"

awk '/^run .*tpm/{found=1} found && /^bind c/{after=1} END{exit after?0:1}' "$TMUX_CONF" && \
  pass "bind c comes after tpm run" || \
  fail "bind c order" "must come after 'run tpm' to override plugins"

echo ""
echo "=== tmux.reset.conf tests ==="

grep -q "bind l select-pane -R" "$RESET_CONF" && \
  grep -q "bind l refresh-client" "$RESET_CONF" && \
  fail "conflicting bind l" "both refresh-client and select-pane -R" || \
  pass "no conflicting bind l"

grep -q "bind -n M-1 select-layout even-horizontal" "$RESET_CONF" && \
  pass "Alt+1 layout switching" || \
  fail "Alt+ layouts" "missing"

grep -q "bind -n M-5 select-layout tiled" "$RESET_CONF" && \
  pass "Alt+5 tiled layout" || \
  fail "Alt+5 tiled" "missing"

grep -q "bind v split-window -h" "$RESET_CONF" && \
  pass "v = horizontal split" || \
  fail "bind v" "missing"

grep -q "bind s split-window -v" "$RESET_CONF" && \
  pass "s = vertical split" || \
  fail "bind s" "missing"

! grep -q "^bind c kill-pane" "$RESET_CONF" && \
  pass "reset.conf no longer binds c to kill-pane" || \
  fail "bind c in reset" "should be removed (moved to post-tpm)"

! grep -q "^bind x swap-pane" "$RESET_CONF" && \
  pass "reset.conf no longer binds x to swap-pane" || \
  fail "bind x in reset" "should be removed (moved to post-tpm)"

! grep -q "^bind c new-window" "$RESET_CONF" && \
  pass "reset.conf does not set c (let plugin default, overridden post-tpm)" || \
  fail "bind c in reset" "should not be in reset.conf"

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  echo "All $PASS tests passed!"
  exit 0
else
  echo "$FAILURES test(s) failed, $PASS passed"
  exit 1
fi
