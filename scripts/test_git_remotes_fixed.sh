#!/usr/bin/env bash
set -euo pipefail

echo "=== Testing Git Remotes Fix in Container ==="

SESSION_NAME="git-remote-fix-$$"

cleanup() {
    echo ""
    echo ">>> Cleaning up"
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    cd ~/projects/sato-be/sato/sato-be
    git worktree remove .worktrees/remotetest --force 2>/dev/null || true
    git branch -D remotetest 2>/dev/null || true
    rm -rf .worktrees/remotetest 2>/dev/null || true
}
trap cleanup EXIT INT

# Must run from a git repository
cd ~/projects/sato-be/sato/sato-be

echo ">>> Current repository: $(pwd)"
echo ">>> Git remotes on host:"
git remote -v

echo ""
echo ">>> Starting container with new_claude.sh"

tmux new-session -d -s "$SESSION_NAME" -x 120 -y 50

cd ~/projects/sato-be/sato/sato-be
tmux send-keys -t "$SESSION_NAME" "cd ~/projects/sato-be/sato/sato-be && /home/yashar/env/scripts/new_claude.sh --container remotetest" C-m

echo ">>> Waiting 8 seconds for Claude to start..."
sleep 8

# Test git remote command
echo ">>> Testing 'git remote -v' inside container..."
tmux send-keys -t "$SESSION_NAME" "git remote -v" C-m

sleep 2

OUTPUT=$(tmux capture-pane -t "$SESSION_NAME" -p -S -30)

echo ""
echo "=== Captured Output: ==="
echo "$OUTPUT" | tail -20

echo ""
echo "=== Analysis ==="

if echo "$OUTPUT" | grep -q "origin.*github.com"; then
    echo "✓ SUCCESS: Git remotes are accessible in container!"
    echo "✓ Found GitHub remote"
    exit 0
elif echo "$OUTPUT" | grep -q "no git remotes found\|fatal.*not a git repository"; then
    echo "✗ FAIL: Git remotes still not accessible"
    exit 1
else
    echo "? UNKNOWN: Could not determine git remote status"
    echo "  Check output above"
    exit 2
fi
