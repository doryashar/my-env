#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
ENV_DIR=$(dirname "$(dirname "$SCRIPT_DIR")")
SYNC_SCRIPT="$ENV_DIR/scripts/sync_encrypted.sh"

echo "Testing sync_encrypted.sh changes..."
echo ""

# Test 1: Script is syntactically correct
echo "Test 1: Checking script syntax..."
if bash -n "$SYNC_SCRIPT"; then
    echo "  ✓ Script syntax is valid"
else
    echo "  ✗ Script has syntax errors"
    exit 1
fi
echo ""

# Test 2: show_changed_files_and_confirm function exists
echo "Test 2: Checking if new functions exist..."
if grep -q "^show_changed_files_and_confirm()" "$SYNC_SCRIPT"; then
    echo "  ✓ show_changed_files_and_confirm function exists"
else
    echo "  ✗ show_changed_files_and_confirm function not found"
    exit 1
fi

if grep -q "^show_file_diff()" "$SYNC_SCRIPT"; then
    echo "  ✓ show_file_diff function exists"
else
    echo "  ✗ show_file_diff function not found"
    exit 1
fi
echo ""

# Test 3: Check that functions are called in the main flow
echo "Test 3: Checking if new functions are integrated..."
if grep -q "show_changed_files_and_confirm \"remote\"" "$SYNC_SCRIPT"; then
    echo "  ✓ Remote sync case uses new function"
else
    echo "  ✗ Remote sync case doesn't use new function"
    exit 1
fi

if grep -q "show_changed_files_and_confirm \"local\"" "$SYNC_SCRIPT"; then
    echo "  ✓ Local sync case uses new function"
else
    echo "  ✗ Local sync case doesn't use new function"
    exit 1
fi
echo ""

# Test 4: Check that old prompts were removed
echo "Test 4: Checking if old simple prompts were removed..."
if ! grep -q 'read -p "An update is available. Do you want to pull the changes' "$SYNC_SCRIPT"; then
    echo "  ✓ Old remote prompt removed"
else
    echo "  ✗ Old remote prompt still exists"
    exit 1
fi

if ! grep -q 'read -p "Local changes detected. Do you want to push the changes' "$SYNC_SCRIPT"; then
    echo "  ✓ Old local prompt removed"
else
    echo "  ✗ Old local prompt still exists"
    exit 1
fi
echo ""

# Test 5: Check for diff viewing capabilities
echo "Test 5: Checking diff viewing capabilities..."
if grep -q "View diff for specific file" "$SYNC_SCRIPT"; then
    echo "  ✓ File diff viewing option present"
else
    echo "  ✗ File diff viewing option not found"
    exit 1
fi

if grep -q "View all diffs" "$SYNC_SCRIPT"; then
    echo "  ✓ View all diffs option present"
else
    echo "  ✗ View all diffs option not found"
    exit 1
fi
echo ""

echo "All tests passed! ✓"
