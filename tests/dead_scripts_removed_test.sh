#!/usr/bin/env bash
# Verifies that dead/abandoned scripts identified in docs/REVIEW_2026-06-16.md
# have been removed from the repo.
#
# These 5 scripts were confirmed unreferenced before deletion:
#   - share_session           (old Synopsys-internal submit_job cruft)
#   - share-session.py        (experimental TCP relay; broken shebang)
#   - mini_irc_server.py      (toy; no auth; race conditions)
#   - monitor_running_apps.sh (broken design; flagged in CODEBASE_REVIEW.md)
#   - ensure_single_instance.sh (only used by monitor_running_apps.sh)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

echo "========================================"
echo "Dead Scripts Removed Tests"
echo "========================================"
echo ""

test_dead_scripts_removed() {
    local removed=0
    local still_present=""
    for script in share_session share-session.py mini_irc_server.py \
                  monitor_running_apps.sh ensure_single_instance.sh; do
        if [[ -e "$ENV_DIR/scripts/tools/$script" ]]; then
            still_present="$still_present $script"
        else
            removed=$((removed + 1))
        fi
    done

    assert_equals 5 "$removed" \
        "All 5 dead scripts must be removed (still present:$still_present)"
}

test_dead_scripts_removed

print_test_summary
