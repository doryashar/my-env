#!/usr/bin/env bash
set -euo pipefail

echo "=== Testing Git Operations in Container ==="

cd ~/projects/sato-be/sato/sato-be || cd /home/yashar/env/scripts

# Clean up old test
git worktree remove .worktrees/git-ops-test --force 2>/dev/null || true
git branch -D git-ops-test 2>/dev/null || true

REPO_ROOT=$(git rev-parse --show-toplevel)
echo ">>> Repository root: $REPO_ROOT"

# Create test worktree
echo ">>> Creating test worktree"
git worktree add .worktrees/git-ops-test -b git-ops-test
cd .worktrees/git-ops-test

# Create a test file
echo "test content" > test_file.txt

echo ""
echo "=== Testing git operations in container ==="

# Test git add
echo ">>> Testing: git add"
docker run --rm \
    -v "$(pwd):/workspace" \
    -v "$REPO_ROOT/.git:$REPO_ROOT/.git" \
    -w /workspace \
    docker/sandbox-templates:claude-code \
    sh -c "git add test_file.txt && echo 'SUCCESS: git add works!'" 2>&1

ADD_RESULT=$?

if [ $ADD_RESULT -eq 0 ]; then
    echo "✓ git add successful"
else
    echo "✗ git add failed"
fi

# Test git status
echo ""
echo ">>> Testing: git status"
docker run --rm \
    -v "$(pwd):/workspace" \
    -v "$REPO_ROOT/.git:$REPO_ROOT/.git" \
    -w /workspace \
    docker/sandbox-templates:claude-code \
    sh -c "git status --short" 2>&1

STATUS_RESULT=$?

if [ $STATUS_RESULT -eq 0 ]; then
    echo "✓ git status successful"
else
    echo "✗ git status failed"
fi

# Cleanup
cd "$REPO_ROOT"
git worktree remove .worktrees/git-ops-test --force
git branch -D git-ops-test

echo ""
if [ $ADD_RESULT -eq 0 ] && [ $STATUS_RESULT -eq 0 ]; then
    echo "✓ SUCCESS: All git operations work in container!"
    exit 0
else
    echo "✗ FAIL: Some git operations failed"
    exit 1
fi
