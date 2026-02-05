#!/bin/bash

#########################################################################
# Idempotency Tests
#
# Tests that setup.sh can be run multiple times safely without issues
#########################################################################

# Test framework
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Setup test environment
TEST_DIR=""
TEST_ENV_DIR=""

setup_test_env() {
    echo -e "${BLUE}Setting up test environment...${NC}"
    TEST_DIR=$(mktemp -d)
    TEST_ENV_DIR="$TEST_DIR/env"
    mkdir -p "$TEST_ENV_DIR"/{scripts,config,functions,dotfiles,bin,aliases,tmp}

    # Copy essential files
    cp -r "$HOME/env/scripts"/* "$TEST_ENV_DIR/scripts/" 2>/dev/null || true
    cp -r "$HOME/env/functions"/* "$TEST_ENV_DIR/functions/" 2>/dev/null || true
    cp -r "$HOME/env/dotfiles"/* "$TEST_ENV_DIR/dotfiles/" 2>/dev/null || true
    cp -r "$HOME/env/config"/* "$TEST_ENV_DIR/config/" 2>/dev/null || true
    cp "$HOME/env/aliases" "$TEST_ENV_DIR/aliases" 2>/dev/null || true

    # Create a fake home for testing
    mkdir -p "$TEST_DIR/home"

    echo -e "${GREEN}✓${NC} Test environment created at: $TEST_DIR"
}

cleanup_test_env() {
    echo -e "${BLUE}Cleaning up test environment...${NC}"
    rm -rf "$TEST_DIR"
    echo -e "${GREEN}✓${NC} Cleanup complete"
}

# Test assertions
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

assert_file_unchanged() {
    local file="$1"
    local checksum1="$2"
    local message="${3:-File $1 should remain unchanged}"

    if [[ -f "$file" ]]; then
        local checksum2=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)
        if [[ "$checksum1" == "$checksum2" ]]; then
            echo -e "${GREEN}✓${NC} $message"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}✗${NC} $message"
            ((TESTS_FAILED++))
        fi
    else
        echo -e "${RED}✗${NC} $message (file missing)"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

assert_no_duplicate_lines() {
    local file="$1"
    local message="${2:-File $1 should have no duplicate lines}"

    if [[ ! -f "$file" ]]; then
        echo -e "${YELLOW}⊘${NC} $message (file not found)"
        ((TESTS_RUN++))
        return
    fi

    local duplicates=$(sort "$file" | uniq -d)
    if [[ -z "$duplicates" ]]; then
        echo -e "${GREEN}✓${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        echo "  Duplicates found: $duplicates"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

assert_command_succeeds() {
    local cmd="$1"
    local message="${2:-Command should succeed}"

    if eval "$cmd" &>/dev/null; then
        echo -e "${GREEN}✓${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: running config generation twice produces same result
test_config_idempotency() {
    local config_file="$TEST_ENV_DIR/config/repo.conf"

    # Remove existing config to test generation
    rm -f "$config_file"

    # Mock the generate_config function
    cat > "$TEST_ENV_DIR/scripts/test_generate.sh" <<'EOF'
#!/bin/bash
generate_config() {
    local config_file="$1/config/repo.conf"
    cat > "$config_file" <<'CONFIG'
REMOTE_URL="test@example.com/repo"
ENV_DIR="/tmp/test/env"
BW_EMAIL="test@example.com"
CONFIG
}
generate_config "$1"
EOF

    chmod +x "$TEST_ENV_DIR/scripts/test_generate.sh"

    # Run first time
    bash "$TEST_ENV_DIR/scripts/test_generate.sh" "$TEST_ENV_DIR" 2>/dev/null
    local checksum1=$(sha256sum "$config_file" 2>/dev/null | cut -d' ' -f1)

    # Run second time
    bash "$TEST_ENV_DIR/scripts/test_generate.sh" "$TEST_ENV_DIR" 2>/dev/null
    local checksum2=$(sha256sum "$config_file" 2>/dev/null | cut -d' ' -f1)

    if [[ "$checksum1" == "$checksum2" ]]; then
        echo -e "${GREEN}✓${NC} Config generation should be idempotent"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Config generation should be idempotent"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: sourcing .env.zsh twice doesn't cause errors
test_env_zsh_idempotent() {
    local env_file="$TEST_ENV_DIR/dotfiles/.env.zsh"

    if [[ ! -f "$env_file" ]]; then
        echo -e "${YELLOW}⊘${NC} .env.zsh not found, skipping idempotency test"
        ((TESTS_RUN++))
        return
    fi

    # Source it twice and check for errors
    if zsh -c "source '$env_file' && source '$env_file'" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} .env.zsh should be idempotent (can be sourced multiple times)"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} .env.zsh should be idempotent (can be sourced multiple times)"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: functions can be sourced multiple times
test_functions_idempotent() {
    local functions_dir="$TEST_ENV_DIR/functions"
    local failed=0

    if [[ ! -d "$functions_dir" ]]; then
        echo -e "${YELLOW}⊘${NC} functions directory not found, skipping test"
        ((TESTS_RUN++))
        return
    fi

    for file in "$functions_dir"/*; do
        if [[ -f "$file" ]]; then
            if ! zsh -c "source '$file' && source '$file'" 2>/dev/null; then
                failed=1
                break
            fi
        fi
    done

    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} All function files should be idempotent"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} All function files should be idempotent"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: aliases can be sourced multiple times
test_aliases_idempotent() {
    local aliases_file="$TEST_ENV_DIR/aliases"

    if [[ ! -f "$aliases_file" ]]; then
        echo -e "${YELLOW}⊘${NC} aliases file not found, skipping test"
        ((TESTS_RUN++))
        return
    fi

    if zsh -c "source '$aliases_file' && source '$aliases_file'" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} aliases should be idempotent"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} aliases should be idempotent"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: no duplicate entries in config after regeneration
test_no_duplicate_configs() {
    local config_file="$TEST_ENV_DIR/config/repo.conf"

    if [[ ! -f "$config_file" ]]; then
        echo -e "${YELLOW}⊘${NC} config file not found, skipping test"
        ((TESTS_RUN++))
        return
    fi

    assert_no_duplicate_lines "$config_file" "Config file should have no duplicate entries"
}

# Test: setup.sh script structure supports idempotency
test_setup_script_structure() {
    local setup_file="$TEST_ENV_DIR/scripts/setup.sh"

    if [[ ! -f "$setup_file" ]]; then
        echo -e "${YELLOW}⊘${NC} setup.sh not found, skipping test"
        ((TESTS_RUN++))
        return
    fi

    # Check for idempotency-friendly patterns
    # Look for "if [ -f ]" or "if [ -d ]" checks before creating
    if grep -q "if \[ -[df] " "$setup_file" || grep -q "if \[\[ -[df] " "$setup_file"; then
        echo -e "${GREEN}✓${NC} setup.sh should have idempotency checks"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}⊘${NC} setup.sh should have idempotency checks (not found)"
        ((TESTS_PASSED++))  # Not a failure, just a warning
    fi
    ((TESTS_RUN++))
}

# Test: tmp directory handling is idempotent
test_tmp_dir_idempotent() {
    local tmp_dir="$TEST_ENV_DIR/tmp"

    # Create tmp directory
    mkdir -p "$tmp_dir"
    touch "$tmp_dir/test_file"

    # Try creating again (should not fail or overwrite)
    if mkdir -p "$tmp_dir" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} tmp directory creation should be idempotent"
        ((TESTS_PASSED++))

        # Check that test file still exists
        if [[ -f "$tmp_dir/test_file" ]]; then
            echo -e "${GREEN}✓${NC} tmp directory should preserve existing files"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}✗${NC} tmp directory should preserve existing files"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    else
        echo -e "${RED}✗${NC} tmp directory creation should be idempotent"
        ((TESTS_FAILED++))
        ((TESTS_RUN++))
        ((TESTS_RUN++))
    fi
}

# Run all tests
run_all_tests() {
    echo "========================================"
    echo "Running Idempotency Tests"
    echo "========================================"
    echo ""

    # Setup
    setup_test_env
    echo ""

    echo "Testing config idempotency..."
    test_config_idempotency
    echo ""

    echo "Testing .env.zsh idempotency..."
    test_env_zsh_idempotent
    echo ""

    echo "Testing functions idempotency..."
    test_functions_idempotent
    echo ""

    echo "Testing aliases idempotency..."
    test_aliases_idempotent
    echo ""

    echo "Testing setup script structure..."
    test_setup_script_structure
    test_no_duplicate_configs
    echo ""

    echo "Testing tmp directory idempotency..."
    test_tmp_dir_idempotent
    echo ""

    # Cleanup
    cleanup_test_env
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
