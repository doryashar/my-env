#!/bin/bash

#########################################################################
# Sync Dotfiles Tests
#
# Tests for the sync_dotfiles.sh script functionality
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
assert_success() {
    local result=$1
    local message="${2:-Command should succeed}"

    if [[ $result -eq 0 ]]; then
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

assert_symlink_exists() {
    local link="$1"
    local message="${2:-Symlink $link should exist}"

    if [[ -L "$link" ]]; then
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
    TEST_HOME="$TEST_DIR/home"

    mkdir -p "$TEST_ENV_DIR"/{dotfiles,config,scripts,functions}
    mkdir -p "$TEST_HOME"

    # Copy actual scripts to test environment
    cp "$HOME/env/functions/common_funcs" "$TEST_ENV_DIR/functions/"
    cp "$HOME/env/scripts/sync_dotfiles.sh" "$TEST_ENV_DIR/scripts/"

    # Create test config
    cat > "$TEST_ENV_DIR/config/dotfiles.conf" << EOF
# Test configuration
DEFAULT_LINK_TYPE="soft"
DEFAULT_CONFLICT_STRATEGY="remote"

# Test mappings
dotfiles/.testrc => ~/.testrc
config/test/* => ~/.config/test/*
EOF

    # Create test dotfile
    echo "# Test config file" > "$TEST_ENV_DIR/dotfiles/.testrc"

    # Create test config directory
    mkdir -p "$TEST_ENV_DIR/config/test"
    echo "test_value=test" > "$TEST_ENV_DIR/config/test/test.conf"

    export ENV_DIR="$TEST_ENV_DIR"
    export HOME="$TEST_HOME"
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "$TEST_DIR"
    unset ENV_DIR
    export HOME="$ORIGINAL_HOME"
}

# Test: config file is parsed correctly
test_config_parsing() {
    setup_test_env

    # Source the sync script to test config loading
    cd "$TEST_ENV_DIR/scripts"
    bash -c "
        source ../../functions/common_funcs
        source sync_dotfiles.sh
        load_config '$TEST_ENV_DIR/config/dotfiles.conf'

        # Check that variables are set
        if [[ '$DEFAULT_LINK_TYPE' == 'soft' ]]; then
            exit 0
        else
            exit 1
        fi
    " && assert_success $? "Config should be parsed with DEFAULT_LINK_TYPE=soft"

    cleanup_test_env
}

# Test: symlink creation
test_symlink_creation() {
    setup_test_env

    # Run sync script
    cd "$TEST_ENV_DIR/scripts"
    bash sync_dotfiles.sh "$TEST_ENV_DIR/config/dotfiles.conf" 2>/dev/null

    # Check if symlink was created
    assert_symlink_exists "$TEST_HOME/.testrc" "Symlink .testrc should be created"

    cleanup_test_env
}

# Test: wildcard pattern matching
test_wildcard_matching() {
    setup_test_env

    # Run sync script
    cd "$TEST_ENV_DIR/scripts"
    bash sync_dotfiles.sh "$TEST_ENV_DIR/config/dotfiles.conf" 2>/dev/null

    # Check if wildcard config was synced
    assert_symlink_exists "$TEST_HOME/.config/test/test.conf" "Wildcard config should be synced"

    cleanup_test_env
}

# Test: script exists and is executable
test_script_exists() {
    assert_file_exists "$HOME/env/scripts/sync_dotfiles.sh" "sync_dotfiles.sh should exist"

    if [[ -x "$HOME/env/scripts/sync_dotfiles.sh" ]]; then
        echo -e "${GREEN}✓${NC} sync_dotfiles.sh should be executable"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} sync_dotfiles.sh should be executable"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: config file exists
test_config_file_exists() {
    assert_file_exists "$HOME/env/config/dotfiles.conf" "dotfiles.conf should exist"
}

# Test: load_config function exists
test_load_config_function() {
    if grep -q "^load_config()" "$HOME/env/scripts/sync_dotfiles.sh"; then
        echo -e "${GREEN}✓${NC} sync_dotfiles.sh should contain load_config function"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} sync_dotfiles.sh should contain load_config function"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: sync_file function exists
test_sync_file_function() {
    if grep -q "^sync_file()" "$HOME/env/scripts/sync_dotfiles.sh"; then
        echo -e "${GREEN}✓${NC} sync_dotfiles.sh should contain sync_file function"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} sync_dotfiles.sh should contain sync_file function"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Save original HOME
ORIGINAL_HOME="$HOME"

# Run all tests
run_all_tests() {
    echo "========================================"
    echo "Running Sync Dotfiles Tests"
    echo "========================================"
    echo ""

    # Basic tests
    test_script_exists
    test_config_file_exists
    test_load_config_function
    test_sync_file_function

    # Functional tests (these modify the filesystem)
    test_config_parsing
    test_symlink_creation
    test_wildcard_matching

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
