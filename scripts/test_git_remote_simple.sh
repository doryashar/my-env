#!/usr/bin/env bash
set -euo pipefail

echo "=== Simple Git Remote Test ==="

cd ~/projects/sato-be/sato/sato-be

# Clean up old worktree
git worktree remove .worktrees/quicktest --force 2>/dev/null || true
git branch -D quicktest 2>/dev/null || true

# Get repo root before worktree
REPO_ROOT=$(git rev-parse --show-toplevel)
echo ">>> Repository root: $REPO_ROOT"

# Create worktree
echo ">>> Creating worktree"
git worktree add .worktrees/quicktest -b quicktest
cd .worktrees/quicktest

echo ""
echo "=== Testing git remote in container ==="

# Test directly with docker
docker run --rm \
    -v "$(pwd):/workspace" \
    -v "$REPO_ROOT/.git:$REPO_ROOT/.git:ro" \
    -w /workspace \
    docker/sandbox-templates:claude-code \
    sh -c "echo 'Git remotes:' && git remote -v && echo '' && echo 'SUCCESS: Git remotes work!'" 2>&1

EXIT_CODE=$?

# Cleanup
cd "$REPO_ROOT"
git worktree remove .worktrees/quicktest --force
git branch -D quicktest

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ Git remotes are working in container!"
    exit 0
else
    echo "✗ Git remotes failed"
    exit 1
fi
