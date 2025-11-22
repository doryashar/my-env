#!/usr/bin/env bash
set -euo pipefail

CLAUDE_CONFIG_DIR="${HOME}/.claude"
CONTAINER_IMAGE="docker/sandbox-templates:claude-code"
TEST_DIR="${1:-/tmp/claude-tmux-test}"
SESSION_NAME="claude-test-$$"

echo "=== Testing Claude Container with tmux ==="
echo "Test directory: $TEST_DIR"
echo ""

# Clean up any existing test directory
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Initialize git repo
git init -q
echo "console.log('test');" > test.js
echo "✓ Created test git repo with test file"

# Cleanup function
cleanup() {
    echo ""
    echo ">>> Cleaning up tmux session"
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo ""
echo "=== Starting Claude in tmux session: $SESSION_NAME ==="

# Create tmux session and run Claude
tmux new-session -d -s "$SESSION_NAME" -x 120 -y 40

# Run the docker command in tmux
tmux send-keys -t "$SESSION_NAME" "docker run --rm -it \
    -v '$CLAUDE_CONFIG_DIR:/home/agent/.claude' \
    -v '$TEST_DIR:/workspace' \
    -w /workspace \
    -e 'DOCKER_SANDBOX_CREDENTIALS=none' \
    '$CONTAINER_IMAGE' \
    claude --dangerously-skip-permissions" C-m

# Wait for Claude to start and render initial screen
echo "Waiting 5 seconds for Claude to start..."
sleep 5

# Capture the screen
echo ""
echo "=== Captured screen content: ==="
tmux capture-pane -t "$SESSION_NAME" -p > /tmp/claude_tmux_output.txt
cat /tmp/claude_tmux_output.txt

echo ""
echo "=== Analysis ==="
if grep -qi "let's get started\|welcome to claude code\|to get started.*api.*key\|would you like to.*log.*in" /tmp/claude_tmux_output.txt; then
    echo "✗ FAIL: Claude showing first-time setup/login screen"
    echo ""
    echo "Problematic lines:"
    grep -i "let's get started\|welcome to claude code\|to get started.*api.*key\|would you like to.*log.*in\|api key" /tmp/claude_tmux_output.txt || true
    exit 1
else
    echo "✓ PASS: No first-time setup screen detected"
    echo ""
    echo "Looking for normal Claude prompt..."
    if grep -qi "how can I help\|what.*work on\|claude" /tmp/claude_tmux_output.txt; then
        echo "✓ Found normal Claude interface"
    else
        echo "? Could not confirm normal interface, check output above"
    fi
fi
