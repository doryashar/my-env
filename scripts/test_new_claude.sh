#!/usr/bin/env bash
set -euo pipefail

SESSION_NAME="new-claude-test-$$"

echo "=== Testing new_claude.sh with tmux ==="

# Cleanup function
cleanup() {
    echo ""
    echo ">>> Killing tmux session and cleaning up"
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

    # Clean up the test worktree
    cd /home/yashar/env/scripts
    git worktree remove .worktrees/test-wt-* --force 2>/dev/null || true
    git branch -D test-wt-* 2>/dev/null || true
    rm -rf .worktrees/test-wt-* 2>/dev/null || true
}
trap cleanup EXIT INT

# Create tmux session
tmux new-session -d -s "$SESSION_NAME" -x 120 -y 40

# Go to scripts directory and run new_claude.sh
cd /home/yashar/env/scripts

# Run new_claude.sh with --container flag
echo "Running: ./new_claude.sh --container test-wt-$$"
tmux send-keys -t "$SESSION_NAME" "cd /home/yashar/env/scripts && ./new_claude.sh --container test-wt-$$" C-m

# Wait for container to start
echo "Waiting 8 seconds for Claude to start..."
sleep 8

# Capture the screen
echo ""
echo "=== Captured screen content: ==="
tmux capture-pane -t "$SESSION_NAME" -p -S -100 > /tmp/new_claude_test.txt
cat /tmp/new_claude_test.txt

echo ""
echo "=== Analysis ==="
if grep -qi "let's get started\|welcome to claude code\|to get started.*enter.*api.*key\|would you like to.*log" /tmp/new_claude_test.txt; then
    echo "✗ FAIL: new_claude.sh showing first-time setup/login screen"
    echo ""
    echo "Problematic lines:"
    grep -i "let's get started\|welcome to claude code\|enter.*api.*key\|log.*in" /tmp/new_claude_test.txt | head -10 || true
    exit 1
else
    echo "✓ PASS: No first-time setup screen detected in new_claude.sh"
fi
