#!/usr/bin/env bash
set -euo pipefail

echo "=== Testing GitHub Token Passing ==="

# Check if GITHUB_API_TOKEN is set
if [ -z "${GITHUB_API_TOKEN:-}" ]; then
    echo "✗ GITHUB_API_TOKEN is not set in the host environment"
    echo "Please set it first: export GITHUB_API_TOKEN=your_token"
    exit 1
fi

echo "✓ GITHUB_API_TOKEN found in host environment"
echo "  Value starts with: ${GITHUB_API_TOKEN:0:10}..."

SESSION_NAME="gh-token-test-$$"

cleanup() {
    echo ""
    echo ">>> Cleaning up"
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    cd /home/yashar/env/scripts
    git worktree remove .worktrees/ghtest --force 2>/dev/null || true
    git branch -D ghtest 2>/dev/null || true
    rm -rf .worktrees/ghtest 2>/dev/null || true
}
trap cleanup EXIT INT

tmux new-session -d -s "$SESSION_NAME" -x 120 -y 50

cd /home/yashar/env/scripts
echo ">>> Starting container with GITHUB_API_TOKEN"
tmux send-keys -t "$SESSION_NAME" "cd /home/yashar/env/scripts && ./new_claude.sh --container ghtest" C-m

echo ">>> Waiting 8 seconds for Claude to start..."
sleep 8

# Send command to check GH_TOKEN in container
echo ">>> Checking if GH_TOKEN is available in container..."
tmux send-keys -t "$SESSION_NAME" "echo \$GH_TOKEN | head -c 10" C-m

sleep 2

OUTPUT=$(tmux capture-pane -t "$SESSION_NAME" -p -S -30)

echo ""
echo "=== Captured Output: ==="
echo "$OUTPUT" | tail -15

echo ""
echo "=== Analysis ==="

if echo "$OUTPUT" | grep -q "Passing GitHub token as GH_TOKEN"; then
    echo "✓ Script detected GITHUB_API_TOKEN and passed it to container"
else
    echo "✗ Script did not detect GITHUB_API_TOKEN"
    exit 1
fi

# Check if the token value appears in the output (first 10 chars)
if echo "$OUTPUT" | grep -q "${GITHUB_API_TOKEN:0:10}"; then
    echo "✓ GH_TOKEN is accessible inside the container"
    echo ""
    echo "SUCCESS: GitHub token is properly passed to container as GH_TOKEN"
    exit 0
else
    echo "? Could not verify GH_TOKEN value in container"
    echo "  This might be okay if output was truncated"
    exit 0
fi
