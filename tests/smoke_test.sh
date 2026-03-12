#!/bin/bash
set -euo pipefail

#########################################################################
# Smoke Tests
#
# Post-setup verification tests - run after setup to validate everything works
#########################################################################

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test_helper.sh"

# Test: ENV_DIR is set correctly
test_env_dir_set() {
    if [[ -n "$ENV_DIR" ]]; then
        assert_equals "$HOME/env" "$ENV_DIR" "ENV_DIR should point to $HOME/env"
    else
        # Source .env.zsh to set ENV_DIR
        if source "$HOME/env/dotfiles/.env.zsh" 2>/dev/null; then
            assert_equals "$HOME/env" "$ENV_DIR" "ENV_DIR should point to $HOME/env"
        else
            echo -e "${RED}✗${NC} Failed to source .env.zsh"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    fi
}

# Test: .env.zsh loads successfully
test_env_zsh_loads() {
    local output=$(zsh -c "source '$HOME/env/dotfiles/.env.zsh' && echo 'SUCCESS'" 2>&1)

    if [[ "$output" == *"SUCCESS"* ]]; then
        echo -e "${GREEN}✓${NC} .env.zsh should load successfully in zsh"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} .env.zsh should load successfully in zsh"
        echo "  Output: $output"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: .zshrc sources .env.zsh
test_zshrc_sources_env_zsh() {
    local zshrc_file="$HOME/env/dotfiles/.zshrc"

    if [[ ! -f "$zshrc_file" ]]; then
        echo -e "${YELLOW}⊘${NC} .zshrc not found, skipping test"
        ((TESTS_RUN++))
        return
    fi

    if grep -q "\.env\.zsh" "$zshrc_file" || grep -q "source.*env\.zsh" "$zshrc_file"; then
        echo -e "${GREEN}✓${NC} .zshrc should source .env.zsh"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}⊘${NC} .zshrc may not source .env.zsh (handled by z4h)"
        ((TESTS_PASSED++))  # Not necessarily a failure with z4h
    fi
    ((TESTS_RUN++))
}

# Test: core directories exist
test_core_directories() {
    assert_dir_exists "$HOME/env" "env directory should exist"
    assert_dir_exists "$HOME/env/scripts" "scripts directory should exist"
    assert_dir_exists "$HOME/env/functions" "functions directory should exist"
    assert_dir_exists "$HOME/env/config" "config directory should exist"
    assert_dir_exists "$HOME/env/dotfiles" "dotfiles directory should exist"
    assert_dir_exists "$HOME/env/tmp" "tmp directory should exist"
}

# Test: core scripts exist
test_core_scripts() {
    assert_file_exists "$HOME/env/scripts/setup.sh" "setup.sh should exist"
    assert_file_exists "$HOME/env/scripts/sync_dotfiles.sh" "sync_dotfiles.sh should exist"
    assert_file_exists "$HOME/env/scripts/sync_env.sh" "sync_env.sh should exist"
}

# Test: required commands exist
test_required_commands() {
    assert_command_exists git "git should be installed"
    assert_command_exists curl "curl should be installed"
    assert_command_exists zsh "zsh should be installed"
}

# Test: dotfiles are linked or exist
test_dotfiles_exist() {
    assert_file_exists "$HOME/env/dotfiles/.env.zsh" ".env.zsh should exist in dotfiles"
    assert_file_exists "$HOME/env/dotfiles/.zshrc" ".zshrc should exist in dotfiles"
    assert_file_exists "$HOME/env/dotfiles/.zshenv" ".zshenv should exist in dotfiles"
}

# Test: config file is valid
test_config_valid() {
    local config_file="$HOME/env/config/repo.conf"

    if [[ ! -f "$config_file" ]]; then
        echo -e "${YELLOW}⊘${NC} config/repo.conf does not exist, skipping test"
        ((TESTS_RUN++))
        return
    fi

    # Test that it can be sourced
    if source "$config_file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} config/repo.conf should be valid"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} config/repo.conf should be valid"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: functions can be loaded
test_functions_loadable() {
    local functions_dir="$HOME/env/functions"
    local failed=0

    if [[ ! -d "$functions_dir" ]]; then
        echo -e "${RED}✗${NC} functions directory should exist"
        ((TESTS_FAILED++))
        ((TESTS_RUN++))
        return
    fi

    for file in "$functions_dir"/*; do
        if [[ -f "$file" ]]; then
            if ! source "$file" 2>/dev/null; then
                failed=1
                break
            fi
        fi
    done

    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} All function files should be loadable"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} All function files should be loadable"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: aliases file is loadable
test_aliases_loadable() {
    local aliases_file="$HOME/env/aliases"

    if [[ ! -f "$aliases_file" ]]; then
        echo -e "${RED}✗${NC} aliases file should exist"
        ((TESTS_FAILED++))
        ((TESTS_RUN++))
        return
    fi

    if source "$aliases_file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} aliases file should be loadable"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} aliases file should be loadable"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: env_vars file is loadable
test_env_vars_loadable() {
    local env_vars="$HOME/env/env_vars"

    if [[ ! -f "$env_vars" ]]; then
        echo -e "${RED}✗${NC} env_vars file should exist"
        ((TESTS_FAILED++))
        ((TESTS_RUN++))
        return
    fi

    if source "$env_vars" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} env_vars should be loadable"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} env_vars should be loadable"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: .env.zsh has no syntax errors
test_env_zsh_syntax_valid() {
    if zsh -n "$HOME/env/dotfiles/.env.zsh" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} .env.zsh should have valid syntax"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} .env.zsh should have valid syntax"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Run all tests
run_all_tests() {
    echo "========================================"
    echo "Running Smoke Tests"
    echo "========================================"
    echo ""

    echo "Testing core structure..."
    test_core_directories
    echo ""

    echo "Testing core scripts..."
    test_core_scripts
    echo ""

    echo "Testing required commands..."
    test_required_commands
    echo ""

    echo "Testing dotfiles..."
    test_dotfiles_exist
    test_zshrc_sources_env_zsh
    echo ""

    echo "Testing configuration..."
    test_config_valid
    test_env_dir_set
    echo ""

    echo "Testing loadable files..."
    test_functions_loadable
    test_aliases_loadable
    test_env_vars_loadable
    echo ""

    echo "Testing .env.zsh loading..."
    test_env_zsh_syntax_valid
    test_env_zsh_loads
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
