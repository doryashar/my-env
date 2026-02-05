# Testing Guide

This document describes the testing infrastructure for the environment repository and how to run tests.

## Overview

The test suite validates the repository from setup to .env.zsh loading. Tests are organized into multiple suites:

| Test Suite | Purpose |
|------------|---------|
| **Setup** | Validates setup script functionality and structure |
| **Environment Loading** | Tests .env.zsh loading, config sources, and function imports |
| **Full Setup Integration** | Tests complete setup flow in a temporary environment |
| **Idempotency** | Verifies setup can be run multiple times safely |
| **Smoke Tests** | Post-setup verification tests |
| **Docker** | Containerized tests in a clean Ubuntu environment |

## Running Tests

### Run All Tests

```bash
# From anywhere in the repo
bash ~/env/tests/run_all_tests.sh

# Or from the tests directory
cd ~/env/tests && bash run_all_tests.sh
```

### Run Specific Test Suites

```bash
# Run specific suites
bash ~/env/tests/run_all_tests.sh setup smoke

# Run only one suite
bash ~/env/tests/run_all_tests.sh --only env_loading

# Skip Docker tests (requires Docker daemon)
bash ~/env/tests/run_all_tests.sh --skip-docker
```

### Run Individual Test Files

```bash
# Setup tests
bash ~/env/tests/setup_test.sh

# Environment loading tests
bash ~/env/tests/env_loading_test.sh

# Full setup integration tests
bash ~/env/tests/full_setup_test.sh

# Idempotency tests
bash ~/env/tests/idempotency_test.sh

# Smoke tests (run after setup)
bash ~/env/tests/smoke_test.sh
```

### Run Docker Tests

```bash
# Build and run Docker test
docker build -t env-test -f ~/env/tests/docker_test/Dockerfile ~/env

# Clean up after test
docker rmi env-test
```

## Test Descriptions

### 1. Setup Tests (`setup_test.sh`)

Tests the setup script infrastructure:

- setup.sh and prerun.sh exist and are executable
- Common functions are sourceable
- Required commands (git, curl) are available
- Config structure is correct
- Required scripts exist
- Setup/prerun functions are defined

### 2. Environment Loading Tests (`env_loading_test.sh`)

Tests that .env.zsh loads correctly:

- .env.zsh file exists
- ENV_DIR is correctly defined
- config/repo.conf exists and is sourceable
- env_vars exists and is sourceable
- All files in functions/ are sourceable
- aliases file is sourceable
- .env.zsh has no syntax errors
- Source order is correct (config → env_vars → functions → aliases)
- ENV_DEBUG function is defined
- tmp directory is used

### 3. Full Setup Integration Tests (`full_setup_test.sh`)

Tests the complete setup flow in isolation:

- Creates a temporary test environment
- Copies repository structure
- Validates all directories and files
- Tests syntax validity of all components
- Verifies test infrastructure exists

### 4. Idempotency Tests (`idempotency_test.sh`)

Tests that running setup multiple times is safe:

- Config generation produces same result on repeat runs
- .env.zsh can be sourced multiple times without errors
- All function files can be sourced multiple times
- aliases can be sourced multiple times
- No duplicate entries in config files
- tmp directory handling preserves existing files

### 5. Smoke Tests (`smoke_test.sh`)

Post-setup verification tests:

- ENV_DIR is set correctly
- .env.zsh loads successfully in zsh
- Core directories exist
- Core scripts exist
- Required commands (git, curl, zsh) are installed
- Dotfiles exist
- Config is valid
- Functions and aliases are loadable
- .env.zsh has valid syntax

### 6. Docker Tests (`docker_test/`)

Containerized tests in a clean environment:

- Runs in Ubuntu 24.04 container
- Tests as new user (testuser)
- Validates repository structure
- Tests core file existence
- Validates .env.zsh syntax
- Tests config loading
- Verifies prerequisites

## Test Framework

All tests use a common bash-based framework with:

```bash
# Assertion functions
assert_equals <expected> <actual> [message]
assert_file_exists <file> [message]
assert_dir_exists <dir> [message]
assert_command_exists <command> [message]
assert_source_succeeds <file> [message]
assert_var_set <var_name> [message]
```

## CI/CD Integration

To integrate with CI/CD:

```yaml
# Example GitHub Actions
- name: Run tests
  run: bash tests/run_all_tests.sh --skip-docker

# With Docker
- name: Run Docker tests
  run: docker build -t env-test -f tests/docker_test/Dockerfile .
```

## Adding New Tests

1. Create a new test file in `tests/`
2. Use the assertion functions from the framework
3. Follow the naming pattern: `<feature>_test.sh`
4. Add to `run_all_tests.sh` if needed
5. Update this documentation

Example:

```bash
#!/bin/bash
source ~/env/tests/setup_test.sh  # For assertion functions

test_my_feature() {
    assert_file_exists "$HOME/env/my_feature" "my_feature should exist"
}

run_all_tests() {
    test_my_feature
}
```

## Troubleshooting

### Docker Tests Fail

- Ensure Docker daemon is running: `sudo systemctl status docker`
- Check Docker permissions: `groups | grep docker`
- Build with no cache: `docker build --no-cache -t env-test -f ...`

### Permission Errors

- Make test scripts executable: `chmod +x tests/*.sh`
- Check file permissions: `ls -la tests/`

### Syntax Errors

- Validate .env.zsh syntax: `zsh -n ~/env/dotfiles/.env.zsh`
- Check test script syntax: `bash -n tests/<test_file>.sh`

## Test Coverage

Current coverage includes:

- [x] Setup script structure and functions
- [x] Configuration file loading
- [x] Environment variable sourcing
- [x] Function loading
- [x] Alias loading
- [x] .env.zsh syntax validity
- [x] Idempotency of core operations
- [x] Docker container testing

Future additions:

- [ ] Integration tests for specific scripts (sync_encrypted, etc.)
- [ ] Performance benchmarks
- [ ] Mock tests for external dependencies (Bitwarden, etc.)
