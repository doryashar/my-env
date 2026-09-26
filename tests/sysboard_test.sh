#!/usr/bin/env bash
# Tests for scripts/tools/sysboard.sh
set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

SYSBOARD="$TEST_DIR/../scripts/tools/sysboard.sh"
FIXTURES="$TEST_DIR/fixtures/sysboard"

test_script_exists_and_sources() {
  assert_file_exists "$SYSBOARD" "sysboard.sh should exist"
  assert_source_succeeds "$SYSBOARD" "sysboard.sh should source cleanly"
}

test_usage_help() {
  local out
  out=$(bash "$SYSBOARD" --help 2>&1)
  assert_contains "$out" "sysboard" "--help should mention sysboard"
  assert_contains "$out" "--report" "--help should mention --report"
}

test_parse_args_defaults() {
  reset_globals
  sb_parse_args
  assert_equals "tui" "$MODE" "default mode is tui"
  assert_equals "1" "$AUTO_REFRESH" "auto refresh on by default"
  assert_equals "5" "$REFRESH_INTERVAL" "default interval 5"
}

test_parse_args_flags() {
  reset_globals
  sb_parse_args --report
  assert_equals "report" "$MODE" "--report sets report mode"

  reset_globals
  sb_parse_args --section docker
  assert_equals "docker" "$SECTION_FILTER" "--section docker sets filter"
  assert_equals "4" "$START_SECTION" "--section docker maps to tab 4"

  reset_globals
  sb_parse_args --no-auto
  assert_equals "0" "$AUTO_REFRESH" "--no-auto disables refresh"

  reset_globals
  sb_parse_args --refresh 10
  assert_equals "10" "$REFRESH_INTERVAL" "--refresh 10 sets interval"
}

test_parse_args_rejects_bad_input() {
  reset_globals
  sb_parse_args --refresh abc 2>/dev/null
  assert_exit_code 1 $? "--refresh abc should return 1"

  reset_globals
  sb_parse_args --section bogus 2>/dev/null
  assert_exit_code 1 $? "--section bogus should return 1"

  reset_globals
  sb_parse_args --wat 2>/dev/null
  assert_exit_code 1 $? "unknown flag should return 1"
}

# reset globals between parse tests (values mirror script defaults)
reset_globals() {
  MODE="tui"
  SECTION_FILTER=""
  AUTO_REFRESH=1
  REFRESH_INTERVAL=5
  START_SECTION=1
}

# --- run tests ---
test_script_exists_and_sources
test_usage_help
test_parse_args_defaults
test_parse_args_flags
test_parse_args_rejects_bad_input

print_test_summary
[[ $TESTS_FAILED -eq 0 ]] || exit 1
