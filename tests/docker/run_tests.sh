#!/bin/bash
set -euo pipefail

DOCKER_TEST_SCRIPT_DIR="/home/testuser/env/tests/docker"
DOCKER_TEST_ENV_DIR="/home/testuser/env"
ORIGINAL_ENV_DIR="/home/testuser/env"

source "$DOCKER_TEST_SCRIPT_DIR/lib/test_framework.sh"
source "$DOCKER_TEST_SCRIPT_DIR/lib/mocks.sh"
source "$DOCKER_TEST_SCRIPT_DIR/lib/state_manager.sh"

SUITES=()
SUITE_PASSED=0
SUITE_FAILED=0
QUIET=${QUIET:-0}

show_help() {
  cat << EOF
Usage: $0 [OPTIONS] [SUITE...]

Run Docker-based tests for the env repository.

Options:
  -h, --help          Show this help message
  -q, --quiet         Suppress detailed output
  -s, --suite NAME    Run specific suite
  -a, --all           Run all suites (default)
  -l, --list          List available suites

Environment Variables:
  USE_REAL_BITWARDEN=true    Use real Bitwarden (requires BW_SESSION)
  USE_REAL_GITHUB=true       Use real GitHub API (requires GH_TOKEN)
  USE_REAL_AGE=true           Use real age encryption

Examples:
  $0                        Run all tests
  $0 01_setup               Run setup tests only
  $0 -s 02_sync_env         Run sync_env tests
  USE_REAL_AGE=true $0 04   Run encrypted tests with real age

EOF
}

list_suites() {
  echo "Available test suites:"
  echo "  01_setup          - Setup script tests (20 tests)"
  echo "  02_sync_env       - Sync env tests (15 tests)"
  echo "  03_sync_dotfiles  - Dotfiles sync tests (25 tests)"
  echo "  04_sync_encrypted - Encrypted sync tests (20 tests)"
  echo "  05_prerun         - Prerun script tests (12 tests)"
  echo "  06_env_zsh        - .env.zsh and functions tests (18 tests)"
  echo "  07_integration    - Integration tests (10 tests)"
}

parse_args() {
  local run_all=false
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      -l|--list)
        list_suites
        exit 0
        ;;
      -q|--quiet)
        QUIET=1
        shift
        ;;
      -s|--suite)
        SUITES+=("$2")
        shift 2
        ;;
      -a|--all)
        run_all=true
        shift
        ;;
      01_setup|02_sync_env|03_sync_dotfiles|04_sync_encrypted|05_prerun|06_env_zsh|07_integration)
        SUITES+=("$1")
        shift
        ;;
      *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done
  
  if [[ ${#SUITES[@]} -eq 0 ]] || [[ "$run_all" == "true" ]]; then
    SUITES=(
      "01_setup"
      "02_sync_env"
      "03_sync_dotfiles"
      "04_sync_encrypted"
      "05_prerun"
      "06_env_zsh"
      "07_integration"
    )
  fi
}

run_suite() {
  local suite_name="$1"
  local suite_script="$DOCKER_TEST_SCRIPT_DIR/suites/${suite_name}.sh"
  
  if [[ ! -f "$suite_script" ]]; then
    echo -e "${RED}Error: Suite not found: $suite_script${NC}"
    return 1
  fi
  
  (
    export SCRIPT_DIR="$DOCKER_TEST_SCRIPT_DIR"
    export ENV_DIR="$DOCKER_TEST_ENV_DIR"
    source "$suite_script"
    
    if declare -f run_all_tests &>/dev/null; then
      run_all_tests
      exit $?
    else
      echo -e "${RED}Error: run_all_tests function not found in $suite_script${NC}"
      exit 1
    fi
  )
  local result=$?
  
  if [[ $result -eq 0 ]]; then
    ((SUITE_PASSED++))
  else
    ((SUITE_FAILED++))
  fi
  
  return $result
}

main() {
  parse_args "$@"
  
  echo -e "${BOLD}========================================${NC}"
  echo -e "${BOLD}ENV Docker Test Suite${NC}"
  echo -e "${BOLD}========================================${NC}"
  echo ""
  
  setup_mocks
  
  local start_time=$(date +%s)
  
  for suite in "${SUITES[@]}"; do
    echo -e "${BLUE}Running suite: $suite${NC}"
    run_suite "$suite" || true
    echo ""
  done
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  teardown_mocks
  
  echo -e "${BOLD}========================================${NC}"
  echo -e "${BOLD}Test Summary${NC}"
  echo -e "${BOLD}========================================${NC}"
  echo ""
  echo "Suites passed: ${SUITE_PASSED}/${#SUITES[@]}"
  echo "Suites failed: ${SUITE_FAILED}/${#SUITES[@]}"
  echo "Duration: ${duration}s"
  echo ""
  
  if [[ $SUITE_FAILED -gt 0 ]]; then
    echo -e "${RED}${BOLD}SOME TESTS FAILED${NC}"
    exit 1
  else
    echo -e "${GREEN}${BOLD}ALL TESTS PASSED${NC}"
    exit 0
  fi
}

main "$@"
