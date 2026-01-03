#!/bin/bash

#########################################################################
# Setup Script Tests
#
# Tests for the setup.sh script functionality
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
        echo "  Actual: $actual"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

assert_command_exists() {
    local cmd="$1"
    local message="${2:-Command $cmd should exist}"

    if command -v "$cmd" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File $file should exist}"

    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✓${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory $dir should exist}"

    if [[ -d "$dir" ]]; then
        echo -e "${GREEN}✓${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Setup test environment
setup_test_env() {
    TEST_DIR=$(mktemp -d)
    TEST_ENV_DIR="$TEST_DIR/env"
    mkdir -p "$TEST_ENV_DIR"/{scripts,config,functions,dotfiles,bin}
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "$TEST_DIR"
}

# Test: setup.sh script exists
test_setup_script_exists() {
    assert_file_exists "$HOME/env/scripts/setup.sh" "setup.sh script should exist"
}

# Test: prerun.sh script exists
test_prerun_script_exists() {
    assert_file_exists "$HOME/env/scripts/prerun.sh" "prerun.sh script should exist"
}

# Test: setup.sh is executable
test_setup_script_executable() {
    if [[ -x "$HOME/env/scripts/setup.sh" ]]; then
        echo -e "${GREEN}✓${NC} setup.sh should be executable"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} setup.sh should be executable"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: common functions are sourced correctly
test_common_functions_source() {
    if source "$HOME/env/functions/common_funcs" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} common_funcs should be sourceable"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} common_funcs should be sourceable"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: validate_commands function works
test_validate_commands() {
    # Both git and curl should be available on most systems
    assert_command_exists git "git command should exist"
    assert_command_exists curl "curl command should exist"
}

# Test: config directory structure
test_config_structure() {
    assert_dir_exists "$HOME/env/config" "config directory should exist"
}

# Test: required scripts exist
test_required_scripts_exist() {
    assert_file_exists "$HOME/env/scripts/sync_dotfiles.sh" "sync_dotfiles.sh should exist"
    assert_file_exists "$HOME/env/scripts/sync_encrypted.sh" "sync_encrypted.sh should exist"
    assert_file_exists "$HOME/env/scripts/sync_env.sh" "sync_env.sh should exist"
}

# Test: functions directory exists and has common_funcs
test_functions_directory() {
    assert_dir_exists "$HOME/env/functions" "functions directory should exist"
    assert_file_exists "$HOME/env/functions/common_funcs" "common_funcs should exist"
}

# Test: setup.sh contains required functions
test_setup_script_functions() {
    local setup_file="$HOME/env/scripts/setup.sh"

    # Check for function definitions
    if grep -q "^generate_config()" "$setup_file"; then
        echo -e "${GREEN}✓${NC} setup.sh should contain generate_config function"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} setup.sh should contain generate_config function"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))

    if grep -q "^install_apt_packages()" "$setup_file"; then
        echo -e "${GREEN}✓${NC} setup.sh should contain install_apt_packages function"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} setup.sh should contain install_apt_packages function"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))

    if grep -q "^setup_zsh()" "$setup_file"; then
        echo -e "${GREEN}✓${NC} setup.sh should contain setup_zsh function"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} setup.sh should contain setup_zsh function"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: prerun.sh contains required functions
test_prerun_script_functions() {
    local prerun_file="$HOME/env/scripts/prerun.sh"

    if grep -q "^is_env_installed()" "$prerun_file"; then
        echo -e "${GREEN}✓${NC} prerun.sh should contain is_env_installed function"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} prerun.sh should contain is_env_installed function"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))

    if grep -q "^check_remote_updates()" "$prerun_file"; then
        echo -e "${GREEN}✓${NC} prerun.sh should contain check_remote_updates function"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} prerun.sh should contain check_remote_updates function"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Run all tests
run_all_tests() {
    echo "========================================"
    echo "Running Setup Script Tests"
    echo "========================================"
    echo ""

    # Setup tests
    test_setup_script_exists
    test_prerun_script_exists
    test_setup_script_executable
    test_common_functions_source

    # Structure tests
    test_config_structure
    test_functions_directory
    test_required_scripts_exist

    # Function tests
    test_setup_script_functions
    test_prerun_script_functions

    # Command tests
    test_validate_commands

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
