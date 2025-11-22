#!/usr/bin/env bash
set -euo pipefail

CLAUDE_CONFIG_DIR="${HOME}/.claude"
CONTAINER_IMAGE="docker/sandbox-templates:claude-code"
TEST_DIR="${1:-/tmp/claude-container-test}"

echo "=== Testing Claude Container Credentials ==="
echo "Test directory: $TEST_DIR"
echo ""

# Clean up any existing test directory
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Initialize git repo (Claude requires git)
git init -q
echo "✓ Created test git repo"

# Check if credentials exist locally
if [ -f "$CLAUDE_CONFIG_DIR/.credentials.json" ]; then
    echo "✓ Local credentials found at $CLAUDE_CONFIG_DIR/.credentials.json"
else
    echo "✗ No local credentials found"
    exit 1
fi

# Test 1: Check if credentials are accessible in container
echo ""
echo "=== Test 1: Checking credential mount ==="
docker run --rm \
    -v "$CLAUDE_CONFIG_DIR:/home/agent/.claude" \
    -v "$TEST_DIR:/workspace" \
    -w /workspace \
    "$CONTAINER_IMAGE" \
    sh -c "if [ -f /home/agent/.claude/.credentials.json ]; then echo '✓ Credentials file mounted'; cat /home/agent/.claude/.credentials.json | head -c 100; echo '...'; else echo '✗ Credentials file NOT found'; exit 1; fi"

# Test 2: Check if Claude recognizes the credentials
echo ""
echo "=== Test 2: Testing Claude authentication ==="
echo "Running: claude --version and checking for auth prompts"

# Create a script to capture output
cat > /tmp/test_claude_auth.sh << 'EOF'
#!/bin/bash
timeout 10 docker run --rm -i \
    -v "$HOME/.claude:/home/agent/.claude" \
    -v "$TEST_DIR:/workspace" \
    -w /workspace \
    -e "DOCKER_SANDBOX_CREDENTIALS=none" \
    docker/sandbox-templates:claude-code \
    sh -c "echo 'Testing auth...' && claude --version 2>&1" || true
EOF

chmod +x /tmp/test_claude_auth.sh
TEST_DIR="$TEST_DIR" /tmp/test_claude_auth.sh > /tmp/claude_test_output.txt 2>&1

echo ""
echo "=== Output captured: ==="
cat /tmp/claude_test_output.txt

echo ""
echo "=== Analysis ==="
if grep -qi "let's get started\|enter.*api.*key\|authenticate\|login" /tmp/claude_test_output.txt; then
    echo "✗ FAIL: Claude is asking for authentication (credentials not being used)"
    echo ""
    echo "Problematic output:"
    grep -i "let's get started\|enter.*api.*key\|authenticate\|login" /tmp/claude_test_output.txt || true
    exit 1
elif grep -qi "version\|2\." /tmp/claude_test_output.txt; then
    echo "✓ PASS: Claude appears to be authenticated (showed version)"
    exit 0
else
    echo "? UNKNOWN: Unable to determine authentication status"
    echo "Full output above for manual review"
    exit 2
fi
