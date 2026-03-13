#!/bin/bash
set -euo pipefail

#########################################################################
# Setup Script Tests
#
# Tests for the setup.sh script functionality
#########################################################################

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test_helper.sh"

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

# Test: setup.sh is executable
test_setup_script_executable() {
    if [[ -x "$HOME/env/scripts/setup.sh" ]]; then
        echo -e "${GREEN}✓${NC} setup.sh should be executable"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} setup.sh should be executable"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test: common functions are sourced correctly
test_common_functions_source() {
    if source "$HOME/env/functions/common_funcs" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} common_funcs should be sourceable"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} common_funcs should be sourceable"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test: validate_commands function works
test_validate_commands() {
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

# Test: setup.sh contains required functions (merged from prerun.sh)
test_setup_script_functions() {
    local setup_file="$HOME/env/scripts/setup.sh"

    if grep -q "^generate_config()" "$setup_file"; then
        echo -e "${GREEN}✓${NC} setup.sh should contain generate_config function"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} setup.sh should contain generate_config function"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    if grep -q "^install_apt_packages()" "$setup_file"; then
        echo -e "${GREEN}✓${NC} setup.sh should contain install_apt_packages function"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} setup.sh should contain install_apt_packages function"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    if grep -q "^setup_zsh()" "$setup_file"; then
        echo -e "${GREEN}✓${NC} setup.sh should contain setup_zsh function"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} setup.sh should contain setup_zsh function"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    if grep -q "^is_env_installed()" "$setup_file"; then
        echo -e "${GREEN}✓${NC} setup.sh should contain is_env_installed function (from prerun.sh)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} setup.sh should contain is_env_installed function (from prerun.sh)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    if grep -q "^create_private_repo()" "$setup_file"; then
        echo -e "${GREEN}✓${NC} setup.sh should contain create_private_repo function"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} setup.sh should contain create_private_repo function"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Run all tests
run_all_tests() {
    echo "========================================"
    echo "Running Setup Script Tests"
    echo "========================================"
    echo ""

    # Setup tests
    test_setup_script_exists
    test_setup_script_executable
    test_common_functions_source

    # Structure tests
    test_config_structure
    test_functions_directory
    test_required_scripts_exist

    # Function tests
    test_setup_script_functions

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
