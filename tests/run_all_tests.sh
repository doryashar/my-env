#!/bin/bash

#########################################################################
# Run All Tests
#
# Master test runner that executes all test suites
#########################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Test tracking
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

# Arrays to track results
declare -a SUITE_NAMES
declare -a SUITE_RESULTS
declare -a SUITE_OUTPUTS

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS] [TEST_SUITE...]"
    echo ""
    echo "Run all or specific test suites for the env repository."
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -q, --quiet             Suppress detailed output"
    echo "  --skip-docker           Skip Docker tests (requires Docker)"
    echo "  --only SUITE            Run only the specified test suite"
    echo ""
    echo "Available Test Suites:"
    echo "  setup                   Test setup script functionality"
    echo "  env_loading             Test .env.zsh loading"
    echo "  full_setup              Test full setup integration"
    echo "  idempotency             Test idempotency"
    echo "  smoke                   Smoke tests (post-setup verification)"
    echo "  docker                  Docker container tests"
    echo "  all                     Run all tests (default)"
    echo ""
    echo "Examples:"
    echo "  $0                      Run all tests"
    echo "  $0 setup smoke          Run setup and smoke tests only"
    echo "  $0 --skip-docker        Run all tests except Docker"
    echo "  $0 --only env_loading   Run only env_loading tests"
    echo ""
}

# Parse arguments
QUIET=0
SKIP_DOCKER=0
SPECIFIC_TESTS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -q|--quiet)
            QUIET=1
            shift
            ;;
        --skip-docker)
            SKIP_DOCKER=1
            shift
            ;;
        --only)
            if [[ -n "$2" ]]; then
                SPECIFIC_TESTS=("$2")
                shift 2
            else
                echo "Error: --only requires a test suite name"
                exit 1
            fi
            ;;
        setup|env_loading|full_setup|idempotency|smoke|docker|all)
            if [[ ${#SPECIFIC_TESTS[@]} -eq 0 || " ${SPECIFIC_TESTS[*]} " =~ " $1 " ]]; then
                SPECIFIC_TESTS+=("$1")
            fi
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Default to all tests if none specified
if [[ ${#SPECIFIC_TESTS[@]} -eq 0 ]]; then
    SPECIFIC_TESTS=(all)
fi

# Function to run a test suite
run_test_suite() {
    local suite_name="$1"
    local suite_script="$2"
    local total_suites=$3

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Running Test Suite $total_suites: $suite_name${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    SUITE_NAMES+=("$suite_name")

    local start_time=$(date +%s)

    if [[ $QUIET -eq 1 ]]; then
        # Run quietly, capture output
        local output
        output=$(bash "$suite_script" 2>&1)
        local exit_code=$?
    else
        # Run with output
        bash "$suite_script"
        local exit_code=$?
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓ Test suite '$suite_name' PASSED${NC} (${duration}s)"
        PASSED_SUITES=$((PASSED_SUITES + 1))
        SUITE_RESULTS+=("PASS")
    else
        echo -e "${RED}✗ Test suite '$suite_name' FAILED${NC} (${duration}s)"
        FAILED_SUITES=$((FAILED_SUITES + 1))
        SUITE_RESULTS+=("FAIL")
    fi

    if [[ $QUIET -eq 1 && $exit_code -ne 0 ]]; then
        echo "$output"
    fi

    echo ""
}

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Track which suites to run
run_setup=0
run_env_loading=0
run_full_setup=0
run_idempotency=0
run_smoke=0
run_docker=0

# Determine which suites to run
for test in "${SPECIFIC_TESTS[@]}"; do
    case $test in
        all)
            run_setup=1
            run_env_loading=1
            run_full_setup=1
            run_idempotency=1
            run_smoke=1
            run_docker=1
            break
            ;;
        setup)
            run_setup=1
            ;;
        env_loading)
            run_env_loading=1
            ;;
        full_setup)
            run_full_setup=1
            ;;
        idempotency)
            run_idempotency=1
            ;;
        smoke)
            run_smoke=1
            ;;
        docker)
            run_docker=1
            ;;
    esac
done

# Skip docker if requested
if [[ $SKIP_DOCKER -eq 1 ]]; then
    run_docker=0
fi

# Counter for suite numbering
suite_counter=0

echo -e "${BOLD}========================================"
echo "Environment Repository Test Suite"
echo "========================================${NC}"
echo ""

# Run test suites
if [[ $run_setup -eq 1 ]]; then
    suite_counter=$((suite_counter + 1))
    run_test_suite "Setup" "$SCRIPT_DIR/setup_test.sh" "$suite_counter"
fi

if [[ $run_env_loading -eq 1 ]]; then
    suite_counter=$((suite_counter + 1))
    run_test_suite "Environment Loading" "$SCRIPT_DIR/env_loading_test.sh" "$suite_counter"
fi

if [[ $run_full_setup -eq 1 ]]; then
    suite_counter=$((suite_counter + 1))
    run_test_suite "Full Setup Integration" "$SCRIPT_DIR/full_setup_test.sh" "$suite_counter"
fi

if [[ $run_idempotency -eq 1 ]]; then
    suite_counter=$((suite_counter + 1))
    run_test_suite "Idempotency" "$SCRIPT_DIR/idempotency_test.sh" "$suite_counter"
fi

if [[ $run_smoke -eq 1 ]]; then
    suite_counter=$((suite_counter + 1))
    run_test_suite "Smoke Tests" "$SCRIPT_DIR/smoke_test.sh" "$suite_counter"
fi

if [[ $run_docker -eq 1 ]]; then
    suite_counter=$((suite_counter + 1))

    # Check if Docker is available
    if command -v docker &> /dev/null; then
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}Running Test Suite $suite_counter: Docker${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""

        TOTAL_SUITES=$((TOTAL_SUITES + 1))
        SUITE_NAMES+=("Docker")

        local start_time=$(date +%s)

        # Build and run Docker test
        if [[ $QUIET -eq 1 ]]; then
            local output
            output=$(docker build -t env-test -f "$SCRIPT_DIR/docker_test/Dockerfile" "$HOME/env" 2>&1)
            local exit_code=$?
        else
            docker build -t env-test -f "$SCRIPT_DIR/docker_test/Dockerfile" "$HOME/env"
            local exit_code=$?
        fi

        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        if [[ $exit_code -eq 0 ]]; then
            echo -e "${GREEN}✓ Test suite 'Docker' PASSED${NC} (${duration}s)"
            PASSED_SUITES=$((PASSED_SUITES + 1))
            SUITE_RESULTS+=("PASS")
        else
            echo -e "${RED}✗ Test suite 'Docker' FAILED${NC} (${duration}s)"
            if [[ $QUIET -eq 1 ]]; then
                echo "$output"
            fi
            FAILED_SUITES=$((FAILED_SUITES + 1))
            SUITE_RESULTS+=("FAIL")
        fi

        # Clean up
        docker rmi env-test &>/dev/null || true
        echo ""
    else
        echo -e "${YELLOW}⊘ Docker not available, skipping Docker tests${NC}"
        echo ""
    fi
fi

# Print summary
echo -e "${BOLD}========================================"
echo "Test Suite Summary"
echo "========================================${NC}"
echo ""
echo "Total test suites: $TOTAL_SUITES"
echo -e "Passed: ${GREEN}$PASSED_SUITES${NC}"
echo -e "Failed: ${RED}$FAILED_SUITES${NC}"
echo ""

if [[ $TOTAL_SUITES -gt 0 ]]; then
    echo "Detailed Results:"
    echo "----------------"
    for i in "${!SUITE_NAMES[@]}"; do
        local name="${SUITE_NAMES[$i]}"
        local result="${SUITE_RESULTS[$i]}"
        if [[ "$result" == "PASS" ]]; then
            echo -e "  ${GREEN}✓${NC} $name"
        else
            echo -e "  ${RED}✗${NC} $name"
        fi
    done
    echo ""
fi

# Exit with appropriate code
if [[ $FAILED_SUITES -gt 0 ]]; then
    echo -e "${RED}${BOLD}Some test suites FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}${BOLD}All test suites PASSED${NC}"
    exit 0
fi
