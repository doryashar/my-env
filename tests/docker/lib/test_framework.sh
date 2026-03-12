#!/bin/bash

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CURRENT_SUITE=""
CURRENT_TEST=""

_assert_result() {
  local result=$1
  local message="$2"
  local expected="${3:-}"
  local actual="${4:-}"
  
  ((TESTS_RUN++))
  
  if [[ $result -eq 0 ]]; then
    echo -e "  ${GREEN}✓${NC} $message"
    ((TESTS_PASSED++))
    return 0
  else
    echo -e "  ${RED}✗${NC} $message"
    if [[ -n "$expected" && -n "$actual" ]]; then
      echo -e "    ${YELLOW}Expected:${NC} $expected"
      echo -e "    ${YELLOW}Actual:${NC} $actual"
    fi
    ((TESTS_FAILED++))
    return 1
  fi
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Values should be equal}"
  [[ "$expected" == "$actual" ]]
  _assert_result $? "$message" "$expected" "$actual"
}

assert_not_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Values should not be equal}"
  [[ "$expected" != "$actual" ]]
  _assert_result $? "$message"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-String should contain substring}"
  [[ "$haystack" == *"$needle"* ]]
  _assert_result $? "$message" "$needle" "$haystack"
}

assert_matches() {
  local string="$1"
  local pattern="$2"
  local message="${3:-String should match pattern}"
  [[ "$string" =~ $pattern ]]
  _assert_result $? "$message" "$pattern" "$string"
}

assert_true() {
  local condition="$1"
  local message="${2:-Condition should be true}"
  if eval "$condition" &>/dev/null; then
    _assert_result 0 "$message" "true" "false"
  else
    _assert_result 1 "$message" "true" "false"
  fi
}

assert_false() {
  local condition="$1"
  local message="${2:-Condition should be false}"
  if eval "$condition" &>/dev/null; then
    _assert_result 1 "$message" "false" "true"
  else
    _assert_result 0 "$message" "false" "true"
  fi
}

assert_success() {
  local exit_code=$1
  local message="${2:-Command should succeed}"
  [[ $exit_code -eq 0 ]]
  _assert_result $? "$message" "exit code 0" "exit code $exit_code"
}

assert_failure() {
  local exit_code=$1
  local message="${2:-Command should fail}"
  [[ $exit_code -ne 0 ]]
  _assert_result $? "$message" "non-zero exit code" "exit code $exit_code"
}

assert_file_exists() {
  local file="$1"
  local message="${2:-File $file should exist}"
  [[ -f "$file" ]]
  _assert_result $? "$message"
}

assert_file_not_exists() {
  local file="$1"
  local message="${2:-File $file should not exist}"
  [[ ! -f "$file" ]]
  _assert_result $? "$message"
}

assert_dir_exists() {
  local dir="$1"
  local message="${2:-Directory $dir should exist}"
  [[ -d "$dir" ]]
  _assert_result $? "$message"
}

assert_dir_not_exists() {
  local dir="$1"
  local message="${2:-Directory $dir should not exist}"
  [[ ! -d "$dir" ]]
  _assert_result $? "$message"
}

assert_symlink_exists() {
  local link="$1"
  local message="${2:-Symlink $link should exist}"
  [[ -L "$link" ]]
  _assert_result $? "$message"
}

assert_symlink_to() {
  local link="$1"
  local target="$2"
  local message="${3:-Symlink $link should point to $target}"
  [[ -L "$link" && "$(readlink -f "$link")" == "$(readlink -f "$target")" ]]
  _assert_result $? "$message"
}

assert_executable() {
  local file="$1"
  local message="${2:-File $file should be executable}"
  [[ -x "$file" ]]
  _assert_result $? "$message"
}

assert_command_exists() {
  local cmd="$1"
  local message="${2:-Command $cmd should exist}"
  command -v "$cmd" &>/dev/null
  _assert_result $? "$message"
}

assert_command_not_exists() {
  local cmd="$1"
  local message="${2:-Command $cmd should not exist}"
  ! command -v "$cmd" &>/dev/null
  _assert_result $? "$message"
}

assert_file_contains() {
  local file="$1"
  local content="$2"
  local message="${3:-File $file should contain $content}"
  [[ -f "$file" ]] && grep -q "$content" "$file"
  _assert_result $? "$message"
}

assert_file_not_contains() {
  local file="$1"
  local content="$2"
  local message="${3:-File $file should not contain $content}"
  [[ ! -f "$file" ]] || ! grep -q "$content" "$file"
  _assert_result $? "$message"
}

assert_exit_code() {
  local expected=$1
  local actual=$2
  local message="${3:-Exit code should be $expected}"
  [[ $expected -eq $actual ]]
  _assert_result $? "$message" "$expected" "$actual"
}

skip_test() {
  local reason="${1:-No reason provided}"
  ((TESTS_SKIPPED++))
  echo -e "  ${YELLOW}⊘${NC} Skipped: $reason"
}

start_suite() {
  CURRENT_SUITE="$1"
  echo ""
  echo -e "${BOLD}${BLUE}========================================${NC}"
  echo -e "${BOLD}${BLUE}Test Suite: $CURRENT_SUITE${NC}"
  echo -e "${BOLD}${BLUE}========================================${NC}"
}

end_suite() {
  echo ""
  echo -e "${BOLD}Suite: $CURRENT_SUITE${NC}"
  echo -e "  ${GREEN}Passed:${NC} $TESTS_PASSED"
  echo -e "  ${RED}Failed:${NC} $TESTS_FAILED"
  echo -e "  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
  echo -e "  Total: $TESTS_RUN"
  echo ""
  
  SUITE_PASSED=$TESTS_PASSED
  SUITE_FAILED=$TESTS_FAILED
  SUITE_SKIPPED=$TESTS_SKIPPED
  SUITE_TOTAL=$TESTS_RUN
  
  TESTS_RUN=0
  TESTS_PASSED=0
  TESTS_FAILED=0
  TESTS_SKIPPED=0
}

run_test() {
  local name="$1"
  local func="$2"
  
  CURRENT_TEST="$name"
  echo -e "${CYAN}[TEST]${NC} $name"
  
  if $func; then
    return 0
  else
    return 1
  fi
}

print_summary() {
  local total_suites=$1
  local passed_suites=$2
  local failed_suites=$3
  
  echo ""
  echo -e "${BOLD}========================================${NC}"
  echo -e "${BOLD}Final Summary${NC}"
  echo -e "${BOLD}========================================${NC}"
  echo ""
  echo "Suites: $passed_suites/$total_suites passed"
  echo ""
  
  if [[ $failed_suites -gt 0 ]]; then
    echo -e "${RED}${BOLD}SOME TESTS FAILED${NC}"
    return 1
  else
    echo -e "${GREEN}${BOLD}ALL TESTS PASSED${NC}"
    return 0
  fi
}

fixture_path() {
  local name="$1"
  echo "$ENV_DIR/tests/docker/fixtures/$name"
}

temp_dir() {
  mktemp -d -t env-test-XXXXXX
}

with_env() {
  local var_name="$1"
  local var_value="$2"
  shift 2
  
  export "$var_name"="$var_value"
  "$@"
  local result=$?
  unset "$var_name"
  return $result
}
