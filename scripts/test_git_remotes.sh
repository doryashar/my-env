#!/usr/bin/env bash
set -euo pipefail

echo "=== Testing Git Remotes in Worktree and Container ==="

# Go to a real git repository
cd ~/projects/sato-be/sato/sato-be || cd /home/yashar/env/scripts

REPO_ROOT=$(git rev-parse --show-toplevel)
echo ">>> Repository root: $REPO_ROOT"

# Create a test worktree
TEST_BRANCH="remotes-test-$$"
TEST_DIR=".worktrees/$TEST_BRANCH"

cleanup() {
    cd "$REPO_ROOT"
    git worktree remove "$TEST_DIR" --force 2>/dev/null || true
    git branch -D "$TEST_BRANCH" 2>/dev/null || true
    rm -rf "$TEST_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo ">>> Creating test worktree"
git worktree add "$TEST_DIR" -b "$TEST_BRANCH"

cd "$TEST_DIR"
echo ">>> Current directory: $(pwd)"

echo ""
echo "=== Host: Checking .git file ==="
cat .git
echo ""

echo "=== Host: Git remotes ==="
git remote -v

echo ""
echo "=== Host: Resolved git directory ==="
GIT_DIR=$(git rev-parse --git-dir)
echo "Git directory: $GIT_DIR"
GIT_COMMON_DIR=$(git rev-parse --git-common-dir)
echo "Git common directory: $GIT_COMMON_DIR"

echo ""
echo "=== Testing in Container ==="

# Test with only worktree mounted (current behavior)
echo ""
echo "--- Test 1: Only worktree mounted ---"
docker run --rm \
    -v "$(pwd):/workspace" \
    -w /workspace \
    docker/sandbox-templates:claude-code \
    sh -c "echo 'Git dir contents:' && cat .git && echo '' && echo 'Attempting git remote:' && git remote -v 2>&1 || echo 'FAILED: Cannot access git remotes'"

echo ""
echo "--- Test 2: With parent .git mounted ---"
docker run --rm \
    -v "$(pwd):/workspace" \
    -v "$REPO_ROOT/.git:$REPO_ROOT/.git:ro" \
    -w /workspace \
    docker/sandbox-templates:claude-code \
    sh -c "echo 'Attempting git remote:' && git remote -v 2>&1 || echo 'FAILED'"

echo ""
echo "=== Analysis ==="
echo "The worktree's .git file points to the parent repository's .git directory."
echo "Container needs access to parent .git for remotes to work."
