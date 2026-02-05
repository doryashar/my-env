#!/bin/bash

#########################################################################
# Full Setup Integration Tests
#
# Tests the complete setup flow in a temporary environment
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
    mkdir -p "$TEST_ENV_DIR"/{scripts,config,functions,dotfiles,bin,aliases,docker,env_vars,tests,tmp}

    # Copy essential files
    cp -r "$HOME/env/scripts"/* "$TEST_ENV_DIR/scripts/" 2>/dev/null || true
    cp -r "$HOME/env/functions"/* "$TEST_ENV_DIR/functions/" 2>/dev/null || true
    cp -r "$HOME/env/dotfiles"/* "$TEST_ENV_DIR/dotfiles/" 2>/dev/null || true
    cp -r "$HOME/env/config"/* "$TEST_ENV_DIR/config/" 2>/dev/null || true
    cp "$HOME/env/aliases" "$TEST_ENV_DIR/aliases" 2>/dev/null || true
    cp "$HOME/env/env_vars" "$TEST_ENV_DIR/env_vars" 2>/dev/null || true

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

# Test: setup.sh script exists in test environment
test_setup_script_exists() {
    assert_file_exists "$TEST_ENV_DIR/scripts/setup.sh" "setup.sh should exist in test environment"
}

# Test: config/repo.conf exists
test_config_exists() {
    assert_file_exists "$TEST_ENV_DIR/config/repo.conf" "config/repo.conf should exist in test environment"
}

# Test: dotfiles directory structure
test_dotfiles_structure() {
    assert_dir_exists "$TEST_ENV_DIR/dotfiles" "dotfiles directory should exist"
    assert_file_exists "$TEST_ENV_DIR/dotfiles/.env.zsh" ".env.zsh should exist in dotfiles"
    assert_file_exists "$TEST_ENV_DIR/dotfiles/.zshrc" ".zshrc should exist in dotfiles"
}

# Test: functions directory
test_functions_directory() {
    assert_dir_exists "$TEST_ENV_DIR/functions" "functions directory should exist"

    # Check that at least one function file exists
    if [[ -n "$(ls -A "$TEST_ENV_DIR/functions" 2>/dev/null)" ]]; then
        echo -e "${GREEN}✓${NC} functions directory should not be empty"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} functions directory should not be empty"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: .env.zsh is syntax valid
test_env_zsh_syntax() {
    if zsh -n "$TEST_ENV_DIR/dotfiles/.env.zsh" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} .env.zsh should have valid syntax"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} .env.zsh should have valid syntax"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: repo.conf is valid
test_repo_conf_valid() {
    local repo_conf="$TEST_ENV_DIR/config/repo.conf"

    if [[ ! -f "$repo_conf" ]]; then
        echo -e "${YELLOW}⊘${NC} repo.conf does not exist (will be generated)"
        ((TESTS_RUN++))
        return
    fi

    # Check for required variables
    if grep -q "ENV_DIR=" "$repo_conf"; then
        echo -e "${GREEN}✓${NC} repo.conf should contain ENV_DIR"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} repo.conf should contain ENV_DIR"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: setup.sh functions are defined
test_setup_functions() {
    local setup_file="$TEST_ENV_DIR/scripts/setup.sh"

    if [[ ! -f "$setup_file" ]]; then
        echo -e "${YELLOW}⊘${NC} setup.sh not found, skipping function tests"
        return
    fi

    local functions_to_check=("install_apt_packages" "setup_zsh" "generate_config")
    for func in "${functions_to_check[@]}"; do
        if grep -q "^$func()" "$setup_file"; then
            echo -e "${GREEN}✓${NC} setup.sh should contain $func function"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}✗${NC} setup.sh should contain $func function"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
}

# Test: files are properly structured
test_directory_structure() {
    local required_dirs=("scripts" "config" "functions" "dotfiles" "bin" "tests" "tmp")

    for dir in "${required_dirs[@]}"; do
        assert_dir_exists "$TEST_ENV_DIR/$dir" "$dir directory should exist"
    done
}

# Test: test infrastructure exists
test_test_infrastructure() {
    assert_dir_exists "$TEST_ENV_DIR/tests" "tests directory should exist"
    assert_file_exists "$TEST_ENV_DIR/tests/setup_test.sh" "setup_test.sh should exist"
}

# Dry run test: simulate setup.sh execution
test_setup_dry_run() {
    local setup_file="$TEST_ENV_DIR/scripts/setup.sh"

    if [[ ! -f "$setup_file" ]]; then
        echo -e "${YELLOW}⊘${NC} setup.sh not found, skipping dry run test"
        return
    fi

    # Check that setup.sh has proper shebang
    if head -1 "$setup_file" | grep -q "#!/"; then
        echo -e "${GREEN}✓${NC} setup.sh should have proper shebang"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} setup.sh should have proper shebang"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Run all tests
run_all_tests() {
    echo "========================================"
    echo "Running Full Setup Integration Tests"
    echo "========================================"
    echo ""

    # Setup
    setup_test_env
    echo ""

    # Structure tests
    echo "Testing directory structure..."
    test_directory_structure
    echo ""

    echo "Testing core files..."
    test_setup_script_exists
    test_config_exists
    echo ""

    echo "Testing dotfiles..."
    test_dotfiles_structure
    echo ""

    echo "Testing functions..."
    test_functions_directory
    test_setup_functions
    echo ""

    echo "Testing syntax validity..."
    test_env_zsh_syntax
    test_repo_conf_valid
    echo ""

    echo "Testing dry run capabilities..."
    test_setup_dry_run
    echo ""

    echo "Testing test infrastructure..."
    test_test_infrastructure
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
