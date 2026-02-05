#!/bin/bash

#########################################################################
# Environment Loading Tests
#
# Tests for .env.zsh loading functionality
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

assert_source_succeeds() {
    local file="$1"
    local message="${2:-File $file should source successfully}"

    if source "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

assert_var_set() {
    local var_name="$1"
    local message="${2:-Variable $var_name should be set}"

    if [[ -n "${!var_name}" ]]; then
        echo -e "${GREEN}✓${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: .env.zsh file exists
test_env_zsh_exists() {
    assert_file_exists "$HOME/env/dotfiles/.env.zsh" ".env.zsh should exist"
}

# Test: ENV_DIR is correctly set in .env.zsh
test_env_dir_definition() {
    local env_file="$HOME/env/dotfiles/.env.zsh"
    if grep -q "^ENV_DIR=" "$env_file"; then
        echo -e "${GREEN}✓${NC} ENV_DIR should be defined in .env.zsh"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} ENV_DIR should be defined in .env.zsh"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: config/repo.conf exists and is valid
test_repo_conf_exists() {
    assert_file_exists "$HOME/env/config/repo.conf" "repo.conf should exist"
}

# Test: repo.conf can be sourced
test_repo_conf_sourceable() {
    local repo_conf="$HOME/env/config/repo.conf"
    if source "$repo_conf" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} repo.conf should be sourceable"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} repo.conf should be sourceable"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: env_vars file exists
test_env_vars_exists() {
    assert_file_exists "$HOME/env/env_vars" "env_vars should exist"
}

# Test: env_vars can be sourced
test_env_vars_sourceable() {
    local env_vars="$HOME/env/env_vars"
    if source "$env_vars" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} env_vars should be sourceable"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} env_vars should be sourceable"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: functions directory exists
test_functions_dir_exists() {
    assert_dir_exists "$HOME/env/functions" "functions directory should exist"
}

# Test: all files in functions/ are sourceable
test_functions_sourceable() {
    local failed=0
    for file in "$HOME/env/functions"/*; do
        if [[ -f "$file" ]]; then
            if ! source "$file" 2>/dev/null; then
                echo -e "${RED}✗${NC} Function file $(basename "$file") is not sourceable"
                failed=1
            fi
        fi
    done

    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} All function files should be sourceable"
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: aliases file exists
test_aliases_file_exists() {
    assert_file_exists "$HOME/env/aliases" "aliases file should exist"
}

# Test: aliases can be sourced
test_aliases_sourceable() {
    local aliases_file="$HOME/env/aliases"
    if source "$aliases_file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} aliases should be sourceable"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} aliases should be sourceable"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: .env.zsh has no syntax errors
test_env_zsh_syntax() {
    if zsh -n "$HOME/env/dotfiles/.env.zsh" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} .env.zsh should have no syntax errors"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} .env.zsh should have no syntax errors"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: .env.zsh sources files in correct order
test_source_order() {
    local env_file="$HOME/env/dotfiles/.env.zsh"

    # Check that config/repo.conf is sourced
    if grep -q "source.*config/repo.conf" "$env_file" || grep -q "\. *config/repo.conf" "$env_file"; then
        echo -e "${GREEN}✓${NC} .env.zsh should source config/repo.conf"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} .env.zsh should source config/repo.conf"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))

    # Check that env_vars is sourced
    if grep -q "source.*env_vars" "$env_file" || grep -q "\. *env_vars" "$env_file"; then
        echo -e "${GREEN}✓${NC} .env.zsh should source env_vars"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} .env.zsh should source env_vars"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: tmp directory exists
test_tmp_dir_exists() {
    assert_dir_exists "$HOME/env/tmp" "tmp directory should exist"
}

# Test: .env.zsh references tmp directory
test_tmp_dir_used() {
    local env_file="$HOME/env/dotfiles/.env.zsh"
    if grep -q "tmp" "$env_file"; then
        echo -e "${GREEN}✓${NC} .env.zsh should reference tmp directory"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} .env.zsh should reference tmp directory"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: ENV_DEBUG function exists
test_env_debug_function() {
    local env_file="$HOME/env/dotfiles/.env.zsh"
    if grep -q "^env_debug()" "$env_file" || grep -q "env_debug.*{.*:" "$env_file"; then
        echo -e "${GREEN}✓${NC} .env.zsh should define env_debug function"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} .env.zsh should define env_debug function"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Run all tests
run_all_tests() {
    echo "========================================"
    echo "Running Environment Loading Tests"
    echo "========================================"
    echo ""

    # File existence tests
    test_env_zsh_exists
    test_repo_conf_exists
    test_env_vars_exists
    test_functions_dir_exists
    test_aliases_file_exists
    test_tmp_dir_exists

    echo ""

    # Sourceable tests
    test_repo_conf_sourceable
    test_env_vars_sourceable
    test_functions_sourceable
    test_aliases_sourceable

    echo ""

    # Structure tests
    test_env_dir_definition
    test_env_zsh_syntax
    test_source_order
    test_env_debug_function
    test_tmp_dir_used

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
