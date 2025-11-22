#!/usr/bin/env bash
set -euo pipefail

SESSION_NAME="detailed-test-$$"

echo "=== Detailed test of new_claude.sh ==="

cleanup() {
    echo ""
    echo ">>> Cleaning up"
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    cd /home/yashar/env/scripts
    git worktree remove .worktrees/detailed-test --force 2>/dev/null || true
    git branch -D detailed-test 2>/dev/null || true
    rm -rf .worktrees/detailed-test 2>/dev/null || true
}
trap cleanup EXIT INT

# Create tmux session
tmux new-session -d -s "$SESSION_NAME" -x 120 -y 50

cd /home/yashar/env/scripts

echo "Running: ./new_claude.sh --container detailed-test"
tmux send-keys -t "$SESSION_NAME" "cd /home/yashar/env/scripts && ./new_claude.sh --container detailed-test" C-m

# Wait longer for Claude to fully initialize
echo "Waiting 12 seconds for Claude to fully initialize..."
sleep 12

# Capture full scrollback
echo ""
echo "=== Captured output (last 200 lines): ==="
tmux capture-pane -t "$SESSION_NAME" -p -S -200 | tee /tmp/detailed_test.txt

echo ""
echo "=== Detailed Analysis ==="
echo ""

echo "Checking for welcome/setup screen..."
if grep -qi "welcome to claude code" /tmp/detailed_test.txt; then
    echo "  ✗ Found: 'Welcome to Claude Code'"
fi

if grep -qi "let's get started" /tmp/detailed_test.txt; then
    echo "  ✗ Found: 'Let's get started'"
fi

if grep -qi "to get started.*enter.*api" /tmp/detailed_test.txt; then
    echo "  ✗ Found: API key prompt"
fi

if grep -qi "would you like to.*log" /tmp/detailed_test.txt; then
    echo "  ✗ Found: Login prompt"
fi

echo ""
echo "Checking for authenticated session..."
if grep -qi "how can i help\|what.*work on\|what.*build" /tmp/detailed_test.txt; then
    echo "  ✓ Found normal Claude prompt"
fi

echo ""
echo "=== Summary ==="
if grep -qiE "welcome to claude code|let's get started|to get started.*enter|would you like to.*log" /tmp/detailed_test.txt; then
    echo "RESULT: ✗ FAIL - First-time setup screen detected"
    exit 1
else
    echo "RESULT: ✓ PASS - No first-time setup detected"
    exit 0
fi
