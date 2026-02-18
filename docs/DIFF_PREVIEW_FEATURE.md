# Diff Preview Feature for sync_encrypted.sh

## Summary

Added an interactive diff preview feature to the `sync_encrypted.sh` script that allows users to review changes before syncing. When changes are detected (either remote, local, or both), the script now displays a list of modified files and provides options to view diffs and confirm before proceeding.

## Changes Made

### New Functions

1. **`show_changed_files_and_confirm(change_type, remote_temp_dir)`**
   - Displays list of changed files
   - Allows user to select specific files to view diffs
   - Provides option to view all diffs at once
   - Prompts for final confirmation before syncing

2. **`show_file_diff(file, change_type)`**
   - Shows diff for a specific file
   - For remote changes: Decrypts both versions and shows unified diff
   - For local changes: Shows current file content

### Updated Workflows

#### Remote-Only Changes
- **Before**: Simple "Do you want to pull the changes?" prompt
- **After**: Shows changed files, allows viewing diffs, then confirms

#### Local-Only Changes
- **Before**: Simple "Local changes detected. Do you want to push?" prompt
- **After**: Shows changed files, allows viewing diffs, then confirms

#### Both Remote and Local Changes
- **Before**: Simple "Both remote and local files have changed. Do you want to merge?" prompt
- **After**: Shows both local and remote changes, confirms before merging

## User Experience

### Example Interaction - Remote Changes

```
====== Remote Changes Detected ======

The following files have changed remotely:

  [1] config/ssh_config
  [2] secrets/api_keys.txt

Options:
  [1-2] - View diff for specific file
  [a]             - View all diffs
  [y]             - Proceed with sync
  [n]             - Cancel sync

Choose an option: 1

====== Diff for: config/ssh_config ======

--- current version
+++ remote version
@@ -1,5 +1,6 @@
 Host github.com
     User git
     IdentityFile ~/.ssh/id_rsa
+    Compression yes

Press Enter to continue...

Do you want to proceed with the sync? (y/n) y
```

## Files Modified

- `scripts/sync_encrypted.sh` - Added diff preview functionality
- `docs/SYNC_ENCRYPTED.md` - Updated documentation

## Files Added

- `tests/sync_encrypted/test_diff_preview.sh` - Test suite for diff preview feature

## Testing

Run the test suite to verify the implementation:

```bash
~/env/tests/sync_encrypted/test_diff_preview.sh
```

All tests pass:
- ✓ Script syntax is valid
- ✓ New functions exist
- ✓ Functions are integrated in sync cases
- ✓ Old prompts removed
- ✓ Diff viewing options present

## Benefits

1. **Safety**: Users can review changes before they're applied
2. **Transparency**: Clear visibility into what will be synced
3. **Flexibility**: Can choose to view specific files or all changes
4. **Control**: Easy to cancel sync if unexpected changes are detected
5. **Debugging**: Helpful for understanding what changed and why

## Implementation Details

- Uses `git diff` to detect changed remote files
- Uses file hash comparison to detect changed local files
- Decrypts encrypted files on-the-fly for diff viewing
- Cleans up temporary decryption files after viewing
- Handles both file and directory changes
