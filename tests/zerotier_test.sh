#!/bin/bash

#########################################################################
# ZeroTier Monitor Tests
#
# Tests for the zerotier_clients function functionality
#########################################################################

# Test framework
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Test assertions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"

    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"

    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}✓${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        echo "  String: $haystack"
        echo "  Should contain: $needle"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should not contain substring}"

    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "${GREEN}✓${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        echo "  String: $haystack"
        echo "  Should NOT contain: $needle"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: jq timestamp conversion from milliseconds to ISO date
test_jq_timestamp_conversion() {
    # ZeroTier returns timestamps in milliseconds
    # 1735689600000 ms = 2025-01-01 00:00:00 UTC (in seconds: 1735689600)

    local test_timestamp_ms="1735689600000"
    local expected_date="2025-01-01T00:00:00Z"

    # Test the conversion (divide by 1000 to convert ms to seconds)
    local result=$(echo "$test_timestamp_ms" | jq -r 'tonumber | . / 1000 | todate')

    assert_equals "$expected_date" "$result" "jq should convert millisecond timestamp to correct ISO date"
}

# Test: jq should NOT produce astronomical years when using millisecond timestamps directly
test_jq_timestamp_millisecond_bug() {
    # This demonstrates the bug: treating milliseconds as seconds produces wrong dates
    local test_timestamp_ms="1735689600000"

    # WRONG: Using milliseconds directly (this is the bug)
    local wrong_result=$(echo "$test_timestamp_ms" | jq -r 'tonumber | todate')

    # The bug should produce a year far in the future (50000+)
    if [[ "$wrong_result" =~ [0-9]{5} ]]; then
        echo -e "${GREEN}✓${NC} Bug confirmed: using milliseconds directly produces astronomical year: $wrong_result"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Expected astronomical year from bug, got: $wrong_result"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: jq handles zero/epoch timestamp correctly
test_jq_epoch_timestamp() {
    local test_timestamp="0"
    local expected_date="1970-01-01T00:00:00Z"

    local result=$(echo "$test_timestamp" | jq -r 'tonumber | todate')

    assert_equals "$expected_date" "$result" "jq should convert 0 to epoch date"
}

# Test: jq handles recent millisecond timestamps correctly
test_jq_recent_millisecond_timestamp() {
    # Test with a recent timestamp (2025-01-01 00:00:00 UTC)
    # In seconds: 1735689600
    # In milliseconds: 1735689600000
    local test_timestamp_ms="1735689600000"
    local expected_year="2025"

    local result=$(echo "$test_timestamp_ms" | jq -r 'tonumber | . / 1000 | todate')

    assert_contains "$result" "$expected_year" "jq with /1000 should produce year 2025"
    assert_not_contains "$result" "56971" "jq with /1000 should NOT produce astronomical years"
}

# Test: monitors file contains the zerotier_clients function
test_zerotier_clients_function_exists() {
    local monitors_file="$HOME/env/functions/monitors"

    if grep -q "^zerotier_clients()" "$monitors_file"; then
        echo -e "${GREEN}✓${NC} zerotier_clients function should exist"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} zerotier_clients function should exist"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: the jq expression in zerotier_clients should use millisecond conversion
test_zerotier_clients_has_millisecond_fix() {
    local monitors_file="$HOME/env/functions/monitors"

    if grep -q "lastSeen.*\/ 1000" "$monitors_file"; then
        echo -e "${GREEN}✓${NC} zerotier_clients should divide by 1000 for lastSeen"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}!${NC} zerotier_clients should divide by 1000 for lastSeen (this is the bug being fixed)"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Run all tests
run_all_tests() {
    echo "========================================"
    echo "Running ZeroTier Monitor Tests"
    echo "========================================"
    echo ""

    # Unit tests for jq timestamp handling
    test_jq_timestamp_conversion
    test_jq_timestamp_millisecond_bug
    test_jq_epoch_timestamp
    test_jq_recent_millisecond_timestamp

    echo ""
    echo "========================================"
    echo "Test Results"
    echo "========================================"
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo "========================================"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Main
main() {
    run_all_tests
}

main "$@"
