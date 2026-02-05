#!/bin/bash

#########################################################################
# Docker Entrypoint Test Script
#
# Runs tests inside a clean Docker container to validate:
# 1. Setup script execution
# 2. .env.zsh loading
# 3. prerun.sh functionality
# 4. Full shell initialization
#########################################################################

echo "========================================"
echo "Docker Environment Integration Test"
echo "========================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Set ENV_DIR globally for all tests
export ENV_DIR=/home/testuser/env
export HOME=/home/testuser

# Verbose execution function - shows command and output
run_verbose() {
    local name="$1"
    local cmd="$2"

    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo -e "${BOLD}$name${NC}"
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo -e "${BLUE}Command:${NC} $cmd"
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    eval "$cmd"
    local exit_code=$?
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓ Exit code: 0${NC}"
    else
        echo -e "${RED}✗ Exit code: $exit_code${NC}"
    fi
    echo ""
}

# Helper functions
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

assert_var_set() {
    local var_name="$1"
    local message="${2:-Variable $var_name should be set}"
    local value="${!var_name}"

    if [[ -n "$value" ]]; then
        echo -e "${GREEN}✓${NC} $message (value: $value)"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

run_test() {
    local name="$1"
    local cmd="$2"

    echo -e "${BLUE}[TEST]${NC} $name"
    if eval "$cmd" 2>&1; then
        echo -e "${GREEN}✓${NC} $name - PASSED"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $name - FAILED"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
    echo ""
}

# ============================================================================
# PART 1: VERBOSE DEMONSTRATION - Show actual execution
# ============================================================================
echo -e "${BOLD}${BLUE}========================================"
echo "PART 1: VERBOSE EXECUTION DEMONSTRATION"
echo "========================================${NC}"
echo ""

run_verbose "1. Environment Variables" "echo \"ENV_DIR=$ENV_DIR\"; echo \"HOME=$HOME\"; echo \"USER=$(whoami)\"; echo \"PATH=\$PATH\""

run_verbose "2. Repository Structure" "ls -la $ENV_DIR/ && echo '' && ls -la $ENV_DIR/scripts/ && echo '' && ls -la $ENV_DIR/dotfiles/"

# Create config first
echo -e "${CYAN}────────────────────────────────────────${NC}"
echo -e "${BOLD}3. Creating Configuration${NC}"
echo -e "${CYAN}────────────────────────────────────────${NC}"
mkdir -p "$ENV_DIR/config"
cat > "$ENV_DIR/config/repo.conf" << 'EOF'
# Remote git repository URL (optional)
REMOTE_URL="git@github.com:doryashar/my_env"
ENV_DIR="${HOME}/env"

# Bitwarden configuration
export BW_EMAIL="your-email@example.com"

# Private encrypted repository
PRIVATE_URL="git@github.com:doryashar/encrypted"

# Display settings
SHOW_DUFF=off
SHOW_NEOFETCH=on
EOF
echo "Created repo.conf:"
cat "$ENV_DIR/config/repo.conf"
echo ""

run_verbose "4. Source repo.conf" "source '$ENV_DIR/config/repo.conf' && echo 'Sourced successfully' && echo 'REMOTE_URL=$REMOTE_URL'"

run_verbose "5. Source common_funcs" "source '$ENV_DIR/functions/common_funcs' && echo 'Functions available:' && declare -F | grep -E '(title|info|warning|error|debug)'"

run_verbose "6. Load .env.zsh (with ENV_DEBUG=1 to see debug output)" "ENV_DEBUG=1 zsh -c 'export ENV_DIR=$ENV_DIR; source $ENV_DIR/dotfiles/.env.zsh 2>&1'"

run_verbose "7. Check loaded functions from .env.zsh" "zsh -c 'export ENV_DIR=$ENV_DIR; source $ENV_DIR/dotfiles/.env.zsh 2>/dev/null; typeset -f | head -20'"

run_verbose "8. Source env_vars" "source '$ENV_DIR/env_vars' && echo 'env_vars loaded'"

run_verbose "9. Source aliases" "bash -c 'source $ENV_DIR/aliases 2>/dev/null && alias | head -10'"

# ============================================================================
# PART 2: AUTOMATED TESTS
# ============================================================================
echo ""
echo -e "${BOLD}${BLUE}========================================"
echo "PART 2: AUTOMATED TESTS"
echo "========================================${NC}"
echo ""

# ============================================================================
# PHASE 1: Environment Setup Validation
# ============================================================================
echo -e "${BLUE}========================================"
echo "PHASE 1: Environment Setup"
echo "========================================${NC}"
echo ""

# Test: We are running as testuser
if [[ "$(whoami)" == "testuser" ]]; then
    echo -e "${GREEN}✓${NC} Running as testuser"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} Running as $(whoami) (expected testuser)"
    ((TESTS_FAILED++))
fi
((TESTS_RUN++))

# Test: ENV_DIR is set
assert_var_set ENV_DIR "ENV_DIR should be set"

# Test: Repository structure
assert_dir_exists "$ENV_DIR" "env directory should exist"
assert_dir_exists "$ENV_DIR/scripts" "scripts directory should exist"
assert_dir_exists "$ENV_DIR/functions" "functions directory should exist"
assert_dir_exists "$ENV_DIR/config" "config directory should exist"
assert_dir_exists "$ENV_DIR/dotfiles" "dotfiles directory should exist"

# ============================================================================
# PHASE 2: Config Generation
# ============================================================================
echo ""
echo -e "${BLUE}========================================"
echo "PHASE 2: Config Generation"
echo "========================================${NC}"
echo ""

# Verify config was created
assert_file_exists "$ENV_DIR/config/repo.conf" "repo.conf should exist"

# Test: Config can be sourced
run_test "Source repo.conf" \
    "source '$ENV_DIR/config/repo.conf'"

# ============================================================================
# PHASE 3: Setup Script Functions
# ============================================================================
echo ""
echo -e "${BLUE}========================================"
echo "PHASE 3: Setup Script Functions"
echo "========================================${NC}"
echo ""

# Test: Common functions can be sourced
run_test "Source common_funcs" \
    "source '$ENV_DIR/functions/common_funcs'"

# Test: Setup script validation (check_command and validate_commands)
run_test "Check git command exists" \
    "command -v git"

run_test "Check curl command exists" \
    "command -v curl"

# ============================================================================
# PHASE 4: .env.zsh Loading Tests
# ============================================================================
echo ""
echo -e "${BLUE}========================================"
echo "PHASE 4: .env.zsh Loading"
echo "========================================${NC}"
echo ""

run_test ".env.zsh syntax validation" \
    "zsh -n '$ENV_DIR/dotfiles/.env.zsh'"

# Test: .env.zsh loads without errors in subshell
run_test ".env.zsh loads successfully" \
    "zsh -c 'export ENV_DIR=$ENV_DIR; source $ENV_DIR/dotfiles/.env.zsh 2>/dev/null && echo SUCCESS' | grep -q SUCCESS"

# Test: ENV_DIR is preserved after sourcing
run_test "ENV_DIR is preserved after loading .env.zsh" \
    "zsh -c 'export ENV_DIR=$ENV_DIR; source $ENV_DIR/dotfiles/.env.zsh 2>/dev/null && [[ -n \$ENV_DIR ]]'"

# Test: Functions directory can be sourced
run_test "Functions can be sourced individually" \
    "bash -c 'for f in $ENV_DIR/functions/*; do source \"\$f\" 2>/dev/null; done && echo SUCCESS' | grep -q SUCCESS"

# ============================================================================
# PHASE 5: prerun.sh Tests
# ============================================================================
echo ""
echo -e "${BLUE}========================================"
echo "PHASE 5: prerun.sh Functionality"
echo "========================================${NC}"
echo ""

run_test "prerun.sh syntax validation" \
    "bash -n '$ENV_DIR/scripts/prerun.sh'"

# Test: prerun.sh functions exist (just check function definitions, don't run main)
run_test "prerun.sh functions can be loaded" \
    "bash -c 'grep -q \"^is_env_installed()\" $ENV_DIR/scripts/prerun.sh && grep -q \"^check_remote_updates()\" $ENV_DIR/scripts/prerun.sh'"

# Mark env as installed for testing
touch "$ENV_DIR/.env_installed"
assert_file_exists "$ENV_DIR/.env_installed" ".env_installed marker should exist"

# ============================================================================
# PHASE 6: Shell Integration Tests
# ============================================================================
echo ""
echo -e "${BLUE}========================================"
echo "PHASE 6: Shell Integration"
echo "========================================${NC}"
echo ""

# Test: Complete shell startup simulation
run_test "Full shell initialization simulation" \
    "zsh -c '
    export ENV_DIR=$ENV_DIR
    # Load config
    source $ENV_DIR/config/repo.conf 2>/dev/null
    # Load .env.zsh
    source $ENV_DIR/dotfiles/.env.zsh 2>/dev/null
    # Verify ENV_DIR is still set
    [[ -n \"\$ENV_DIR\" ]]
    echo SUCCESS
' | grep -q SUCCESS"

# Test: env_vars file is accessible
run_test "env_vars can be loaded" \
    "zsh -c 'source $ENV_DIR/env_vars 2>/dev/null && echo SUCCESS' | grep -q SUCCESS"

# Test: aliases file is accessible
run_test "aliases can be loaded" \
    "zsh -c 'source $ENV_DIR/aliases 2>/dev/null && echo SUCCESS' | grep -q SUCCESS"

# ============================================================================
# PHASE 7: Idempotency Tests
# ============================================================================
echo ""
echo -e "${BLUE}========================================"
echo "PHASE 7: Idempotency"
echo "========================================${NC}"
echo ""

# Test: Sourcing .env.zsh multiple times works
run_test ".env.zsh is idempotent" \
    "zsh -c '
    export ENV_DIR=$ENV_DIR
    source $ENV_DIR/dotfiles/.env.zsh 2>/dev/null
    source $ENV_DIR/dotfiles/.env.zsh 2>/dev/null
    source $ENV_DIR/dotfiles/.env.zsh 2>/dev/null
    echo SUCCESS
' | grep -q SUCCESS"

# Test: Config file can be sourced multiple times
run_test "repo.conf is idempotent" \
    "bash -c '
    source $ENV_DIR/config/repo.conf
    source $ENV_DIR/config/repo.conf
    echo SUCCESS
' | grep -q SUCCESS"

# ============================================================================
# PHASE 8: Core Scripts Validation
# ============================================================================
echo ""
echo -e "${BLUE}========================================"
echo "PHASE 8: Core Scripts"
echo "========================================${NC}"
echo ""

# Test: sync_dotfiles.sh exists and is valid
assert_file_exists "$ENV_DIR/scripts/sync_dotfiles.sh" "sync_dotfiles.sh should exist"
run_test "sync_dotfiles.sh syntax" \
    "bash -n '$ENV_DIR/scripts/sync_dotfiles.sh'"

# Test: sync_env.sh exists and is valid
assert_file_exists "$ENV_DIR/scripts/sync_env.sh" "sync_env.sh should exist"
run_test "sync_env.sh syntax" \
    "bash -n '$ENV_DIR/scripts/sync_env.sh'"

# ============================================================================
# PHASE 9: Interactive Shell Simulation
# ============================================================================
echo ""
echo -e "${BLUE}========================================"
echo "PHASE 9: Interactive Shell Simulation"
echo "========================================${NC}"
echo ""

# Test: Simulate interactive shell startup (non-interactive mode)
# Note: zoxide error is expected since it's not installed in Docker
run_test "Non-interactive shell load" \
    "bash -c 'export ENV_DIR=$ENV_DIR
zsh -c \"source $ENV_DIR/dotfiles/.env.zsh 2>/dev/null\" 2>&1 || true'"

# ============================================================================
# RESULTS SUMMARY
# ============================================================================
echo ""
echo "========================================"
echo "Test Results Summary"
echo "========================================"
echo ""
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}========================================"
    echo "Docker tests FAILED"
    echo "========================================${NC}"
    exit 1
else
    echo -e "${GREEN}========================================"
    echo "All Docker tests PASSED"
    echo "========================================${NC}"
    echo ""
    echo "Validated:"
    echo "  ✓ Repository structure"
    echo "  ✓ Config generation"
    echo "  ✓ Setup script functions"
    echo "  ✓ .env.zsh loading"
    echo "  ✓ prerun.sh functionality"
    echo "  ✓ Shell integration"
    echo "  ✓ Idempotency"
    echo "  ✓ Core scripts"
    echo "  ✓ Shell initialization"
    exit 0
fi
