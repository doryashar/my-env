#!/usr/bin/env bash
set -euo pipefail

CLAUDE_CONFIG_DIR="${HOME}/.claude"
CONTAINER_IMAGE="docker/sandbox-templates:claude-code"
TEST_DIR="${1:-/tmp/claude-interactive-test}"

echo "=== Testing Claude Container Interactive Startup ==="
echo "Test directory: $TEST_DIR"
echo ""

# Clean up any existing test directory
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Initialize git repo
git init -q
echo "✓ Created test git repo"

# Create a test file to check
echo "console.log('test');" > test.js

echo ""
echo "=== Starting Claude interactively and capturing first 50 lines ==="
echo "Press Ctrl+C after you see the initial screen"
echo ""

# Use script command to capture interactive session
script -q -c "timeout 15 docker run --rm -it \
    -v '$CLAUDE_CONFIG_DIR:/home/agent/.claude' \
    -v '$TEST_DIR:/workspace' \
    -w /workspace \
    -e 'DOCKER_SANDBOX_CREDENTIALS=none' \
    '$CONTAINER_IMAGE' \
    claude --dangerously-skip-permissions 2>&1 || true" /tmp/claude_interactive_output.txt

echo ""
echo "=== Captured output (first 100 lines): ==="
head -100 /tmp/claude_interactive_output.txt | cat -v

echo ""
echo "=== Analysis ==="
if grep -qi "let's get started\|welcome.*claude.*code\|enter.*your.*api.*key" /tmp/claude_interactive_output.txt; then
    echo "✗ FAIL: Claude showing first-time setup screen"
    echo ""
    grep -i "let's get started\|welcome.*claude.*code\|enter.*your.*api.*key" /tmp/claude_interactive_output.txt | head -5
else
    echo "✓ PASS: Claude appears authenticated (no first-time setup prompt)"
fi

# Clean up
rm -rf "$TEST_DIR"
