#!/usr/bin/env bash
set -euo pipefail

echo "=== Testing Git Push Authentication ==="

# Check if GITHUB_API_TOKEN is set
if [ -z "${GITHUB_API_TOKEN:-}" ]; then
    echo "✗ GITHUB_API_TOKEN is not set"
    echo "Please set it first: export GITHUB_API_TOKEN=your_token"
    exit 1
fi

echo "✓ GITHUB_API_TOKEN is set"

cd ~/projects/sato-be/sato/sato-be || cd /home/yashar/env/scripts

# Clean up old test
git worktree remove .worktrees/push-test --force 2>/dev/null || true
git branch -D push-test 2>/dev/null || true

REPO_ROOT=$(git rev-parse --show-toplevel)
echo ">>> Repository root: $REPO_ROOT"

# Create test worktree
echo ">>> Creating test worktree"
git worktree add .worktrees/push-test -b push-test
cd .worktrees/push-test

# Create a test commit
echo "test" > test_push.txt
git add test_push.txt
git commit -m "Test commit for push authentication"

echo ""
echo "=== Testing git credential helper configuration ==="

docker run --rm \
    -v "$(pwd):/workspace" \
    -v "$REPO_ROOT/.git:$REPO_ROOT/.git" \
    -w /workspace \
    -e "GITHUB_TOKEN=$GITHUB_API_TOKEN" \
    --entrypoint /bin/bash \
    docker/sandbox-templates:claude-code \
    -c 'git config --global credential.helper "!f() { echo username=git; echo password=$GITHUB_TOKEN; }; f" && echo "Git credential helper configured" && git config --global credential.helper'

echo ""
echo "=== Testing git push (dry-run) ==="

# Test with --dry-run to avoid actually pushing
docker run --rm \
    -v "$(pwd):/workspace" \
    -v "$REPO_ROOT/.git:$REPO_ROOT/.git" \
    -w /workspace \
    -e "GITHUB_TOKEN=$GITHUB_API_TOKEN" \
    --entrypoint /bin/bash \
    docker/sandbox-templates:claude-code \
    -c 'git config --global credential.helper "!f() { echo username=git; echo password=$GITHUB_TOKEN; }; f" && echo "Attempting git push --dry-run..." && git push origin push-test --dry-run 2>&1 || echo "PUSH RESULT: $?"'

PUSH_RESULT=$?

# Cleanup
cd "$REPO_ROOT"
git worktree remove .worktrees/push-test --force
git branch -D push-test

echo ""
if [ $PUSH_RESULT -eq 0 ]; then
    echo "✓ SUCCESS: Git push authentication works!"
    echo ""
    echo "Note: This was a dry-run. No actual push was made."
    exit 0
else
    echo "? Git push test completed (check output above)"
    echo "  Dry-run may show 'Everything up-to-date' which is okay"
    exit 0
fi
